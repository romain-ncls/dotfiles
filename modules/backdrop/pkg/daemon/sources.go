package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"math/rand/v2"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const userAgent = "backdrop/0.1 (+https://github.com/romain-ncls/dotfiles)"

var httpClient = &http.Client{Timeout: 2 * time.Minute}

// sources lists what each source's listing call returns. A listing is cheap
// metadata: images are only downloaded for the candidates the model picks.
var sources = map[string]func(ctx context.Context, d *Daemon, n int) ([]*Candidate, error){
	"spotlight": listSpotlight,
	"bing":      listBing,
	"wallhaven": listWallhaven,
}

func getJSON(ctx context.Context, u string, v any) error {
	req, err := http.NewRequestWithContext(ctx, "GET", u, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", userAgent)
	resp, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("GET %s: %s", u, resp.Status)
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 8<<20)).Decode(v)
}

func getText(ctx context.Context, u string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", u, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", userAgent)
	resp, err := httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("GET %s: %s", u, resp.Status)
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	return string(b), err
}

// download saves u as dir/stem.<ext> and returns the path.
func download(ctx context.Context, u, dir, stem string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", u, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", userAgent)
	resp, err := httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("GET %s: %s", u, resp.Status)
	}

	// Hidden temp name: the wallpaper plugin ignores dot files.
	f, err := os.CreateTemp(dir, ".download-*")
	if err != nil {
		return "", err
	}
	_, err = io.Copy(f, io.LimitReader(resp.Body, 50<<20))
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		os.Remove(f.Name())
		return "", err
	}
	ext := ".jpg"
	if p, _ := url.Parse(u); p != nil && strings.EqualFold(path.Ext(p.Path), ".png") ||
		strings.Contains(resp.Header.Get("Content-Type"), "png") {
		ext = ".png"
	}
	dst := filepath.Join(dir, stem+ext)
	if err := os.Rename(f.Name(), dst); err != nil {
		os.Remove(f.Name())
		return "", err
	}
	return dst, nil
}

// fileStem turns a candidate ID into a safe file name.
func fileStem(id string) string {
	return strings.Map(func(r rune) rune {
		if r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' || r == '_' {
			return r
		}
		return '-'
	}, id)
}

func shortHash(s string) string {
	h := sha256.Sum256([]byte(s))
	return hex.EncodeToString(h[:8])
}

// Windows Spotlight: the feed behind the Windows lock screen and desktop
// spotlight. Each call returns 4 random picks from a large curated set.
func listSpotlight(ctx context.Context, d *Daemon, n int) ([]*Candidate, error) {
	q := url.Values{
		"placement": {"88000820"},
		"bcnt":      {"4"},
		"fmt":       {"json"},
		"country":   {d.cfg.Country},
		"locale":    {d.cfg.Market},
	}
	u := "https://fd.api.iris.microsoft.com/v4/api/selection?" + q.Encode()

	var out []*Candidate
	var errs []error
	// Fetch about twice what is needed so the model has a choice.
	for range min(4, n/2+1) {
		var resp struct {
			Batchrsp struct {
				Items []struct {
					Item string `json:"item"`
				} `json:"items"`
			} `json:"batchrsp"`
		}
		if err := getJSON(ctx, u, &resp); err != nil {
			errs = append(errs, err)
			continue
		}
		for _, it := range resp.Batchrsp.Items {
			var item struct {
				Ad struct {
					LandscapeImage struct {
						Asset string `json:"asset"`
					} `json:"landscapeImage"`
					IconHoverText string `json:"iconHoverText"`
					Title         string `json:"title"`
					Description   string `json:"description"`
					Copyright     string `json:"copyright"`
					CtaURI        string `json:"ctaUri"`
					EntityID      string `json:"entityId"`
				} `json:"ad"`
			}
			if json.Unmarshal([]byte(it.Item), &item) != nil || item.Ad.LandscapeImage.Asset == "" {
				continue
			}
			ad := item.Ad
			// "Marmaris, Türkiye\r\n© Anton Petrus / Getty Images\r\nRight-click to learn more"
			place, _, _ := strings.Cut(ad.IconHoverText, "\r\n")
			id := ad.EntityID
			if id == "" {
				id = shortHash(ad.LandscapeImage.Asset)
			}
			out = append(out, &Candidate{
				ID:       "spotlight:" + id,
				Source:   "spotlight",
				Title:    ad.Title,
				Place:    place,
				Credit:   ad.Copyright,
				InfoURL:  strings.TrimPrefix(ad.CtaURI, "microsoft-edge:"),
				ImageURL: ad.LandscapeImage.Asset,
				Words:    keywords(ad.Title, place, ad.Description),
			})
		}
	}
	if len(out) > 0 {
		return out, nil
	}
	return nil, errors.Join(errs...)
}

var (
	bingCredit = regexp.MustCompile(`^(.*?)\s*\((©.*)\)\s*$`)
	// "/th?id=OHR.BoriesPoppies_FR-FR9955316118" -> "BoriesPoppies"
	bingName = regexp.MustCompile(`OHR\.([A-Za-z0-9]+)_`)
	// Bing's picture names are English CamelCase in every edition.
	camelWord = regexp.MustCompile(`[A-Z][a-z]+|[a-z]+`)
)

// nameWords turns a Bing picture name such as "BoriesPoppies" into
// keywords. Its texts are in the edition's language, the name is not: this
// keeps what the model learns from Bing consistent with Spotlight's words.
func nameWords(name string) []string {
	return keywords(strings.Join(camelWord.FindAllString(name, -1), " "))
}

// Bing: the homepage picture of the day, in the edition KDE's Picture of the
// Day shows (Bing picks it from the IP address when no market is given).
// Bing's API only goes back two weeks, so most pictures come from the
// edition's archive on bingwallpaper.anerg.com.
func listBing(ctx context.Context, d *Daemon, _ int) ([]*Candidate, error) {
	out, err := listBingDaily(ctx, d)
	if d.cfg.Bing.Archive != "" {
		archive, archiveErr := listBingArchive(ctx, d)
		out = append(out, archive...)
		err = errors.Join(err, archiveErr)
	}
	return out, err
}

func listBingDaily(ctx context.Context, d *Daemon) ([]*Candidate, error) {
	var out []*Candidate
	var errs []error
	for _, idx := range []int{0, 7} {
		var resp struct {
			Images []struct {
				URLBase       string `json:"urlbase"`
				Copyright     string `json:"copyright"`
				CopyrightLink string `json:"copyrightlink"`
				Title         string `json:"title"`
			} `json:"images"`
		}
		u := fmt.Sprintf("https://www.bing.com/HPImageArchive.aspx?format=js&n=8&idx=%d&mkt=%s", idx, url.QueryEscape(d.cfg.Bing.Market))
		if err := getJSON(ctx, u, &resp); err != nil {
			errs = append(errs, err)
			continue
		}
		for _, im := range resp.Images {
			name := bingName.FindStringSubmatch(im.URLBase)
			if name == nil {
				continue
			}
			// "Village des Bories, Gordes, Provence-Alpes-Côte d’Azur (© AGUILAR PATRICE/Alamy)"
			place, credit := im.Copyright, ""
			if m := bingCredit.FindStringSubmatch(im.Copyright); m != nil {
				place, credit = m[1], m[2]
			}
			out = append(out, &Candidate{
				// The name, not Bing's hash: the archive knows pictures by name.
				ID:       "bing:" + name[1],
				Source:   "bing",
				Title:    im.Title,
				Place:    place,
				Credit:   credit,
				InfoURL:  im.CopyrightLink,
				ImageURL: "https://www.bing.com" + im.URLBase + "_UHD.jpg",
				Words:    nameWords(name[1]),
			})
		}
	}
	return out, errors.Join(errs...)
}

const bingArchiveSite = "https://bingwallpaper.anerg.com/"

var (
	// The archive has pictures of at least 1920x1080 from March 2019 on.
	bingArchiveStart = time.Date(2019, time.March, 1, 0, 0, 0, 0, time.UTC)
	// <a class="wallpaper-card" href="/detail/fr/BoriesPoppies" aria-label="View Village des Bories, ...">
	archiveCard = regexp.MustCompile(`<a class="wallpaper-card" href="/detail/[a-z-]+/([A-Za-z0-9_]+)" aria-label="View ([^"]*)"`)
	// Older pictures carry their size in the name: "ZumwaltPrairie_1920x1080".
	archiveSize = regexp.MustCompile(`_(\d+)x(\d+)$`)
	ldJSON      = regexp.MustCompile(`(?s)<script type="application/ld\+json">(.*?)</script>`)
)

// listBingArchive lists a random past month of the archive. The site has
// no API: this reads its HTML, so a redesign breaks it (loudly: see the
// error) while the daily feed keeps working.
func listBingArchive(ctx context.Context, d *Daemon) ([]*Candidate, error) {
	now := time.Now()
	months := (now.Year()-bingArchiveStart.Year())*12 + int(now.Month()-bingArchiveStart.Month())
	month := bingArchiveStart.AddDate(0, rand.IntN(max(1, months)), 0).Format("200601")
	u := bingArchiveSite + "archive/" + d.cfg.Bing.Archive + "/" + month
	page, err := getText(ctx, u)
	if err != nil {
		return nil, err
	}
	cards := archiveCard.FindAllStringSubmatch(page, -1)
	if len(cards) == 0 {
		return nil, fmt.Errorf("no pictures found on %s, did the page layout change?", u)
	}
	var out []*Candidate
	for _, card := range cards {
		slug, name := card[1], card[1]
		if m := archiveSize.FindStringSubmatch(slug); m != nil {
			w, _ := strconv.Atoi(m[1])
			h, _ := strconv.Atoi(m[2])
			if w < d.cfg.MinWidth || h < d.cfg.MinHeight {
				continue
			}
			name = strings.TrimSuffix(slug, m[0])
		}
		out = append(out, &Candidate{
			ID:       "bing:" + name,
			Source:   "bing",
			Title:    html.UnescapeString(card[2]),
			InfoURL:  bingArchiveSite + "detail/" + d.cfg.Bing.Archive + "/" + slug,
			ImageURL: "https://img.nanxiongnandi.com/" + month + "/" + slug + ".jpg",
			Words:    nameWords(name),
		})
	}
	return out, nil
}

// enrichBingArchive reads the photo credit, and the image URL in case the
// archive moves its files, from the picture page's structured data.
func enrichBingArchive(ctx context.Context, c *Candidate) error {
	page, err := getText(ctx, c.InfoURL)
	if err != nil {
		return err
	}
	m := ldJSON.FindStringSubmatch(page)
	if m == nil {
		return fmt.Errorf("no structured data on %s", c.InfoURL)
	}
	var ld struct {
		Graph []struct {
			Type       string `json:"@type"`
			ContentURL string `json:"contentUrl"`
			CreditText string `json:"creditText"`
		} `json:"@graph"`
	}
	if err := json.Unmarshal([]byte(m[1]), &ld); err != nil {
		return fmt.Errorf("%s: %w", c.InfoURL, err)
	}
	for _, g := range ld.Graph {
		if g.Type == "ImageObject" {
			if g.ContentURL != "" {
				c.ImageURL = g.ContentURL
			}
			c.Credit = g.CreditText
		}
	}
	return nil
}

// Wallhaven: community wallpapers, searched in the SFW toplist so quality
// stays high. Queries come from the config plus tags of liked pictures.
func listWallhaven(ctx context.Context, d *Daemon, _ int) ([]*Candidate, error) {
	d.mu.Lock()
	query := d.wallhavenQuery()
	d.mu.Unlock()

	q := url.Values{
		"q":          {query},
		"categories": {d.cfg.Wallhaven.Categories},
		"purity":     {"100"},
		"sorting":    {"toplist"},
		"topRange":   {[]string{"1M", "3M", "6M", "1y"}[rand.IntN(4)]},
		"atleast":    {fmt.Sprintf("%dx%d", d.cfg.MinWidth, d.cfg.MinHeight)},
		"ratios":     {"16x9,16x10"},
	}
	var resp struct {
		Data []struct {
			ID   string `json:"id"`
			URL  string `json:"url"`
			Path string `json:"path"`
		} `json:"data"`
	}
	for _, page := range []int{1 + rand.IntN(3), 1} {
		q.Set("page", fmt.Sprint(page))
		if err := getJSON(ctx, "https://wallhaven.cc/api/v1/search?"+q.Encode(), &resp); err != nil {
			return nil, err
		}
		if len(resp.Data) > 0 {
			break
		}
	}
	out := make([]*Candidate, 0, len(resp.Data))
	for _, w := range resp.Data {
		out = append(out, &Candidate{
			ID:       "wallhaven:" + w.ID,
			Source:   "wallhaven",
			Title:    "Wallhaven " + w.ID,
			InfoURL:  w.URL,
			ImageURL: w.Path,
		})
	}
	return out, nil
}

// enrichWallhaven fetches the tags of a picture the model picked: search
// results do not carry them, and they are what the model learns from.
func enrichWallhaven(ctx context.Context, c *Candidate) error {
	var resp struct {
		Data struct {
			Tags []struct {
				ID   int    `json:"id"`
				Name string `json:"name"`
			} `json:"tags"`
			Uploader struct {
				Username string `json:"username"`
			} `json:"uploader"`
			Source string `json:"source"`
		} `json:"data"`
	}
	id := strings.TrimPrefix(c.ID, "wallhaven:")
	if err := getJSON(ctx, "https://wallhaven.cc/api/v1/w/"+id, &resp); err != nil {
		return err
	}
	var names []string
	for _, t := range resp.Data.Tags {
		name := strings.ToLower(t.Name)
		c.Tags = append(c.Tags, Tag{ID: t.ID, Name: name})
		names = append(names, name)
	}
	if len(names) > 0 {
		c.Title = strings.Join(names[:min(3, len(names))], " · ")
	}
	c.Words = keywords(names...)
	if u := resp.Data.Uploader.Username; u != "" {
		c.Credit = "Uploaded by " + u + " on Wallhaven"
	}
	// Prefer the artist's page (ArtStation, DeviantArt...) when known.
	if src := resp.Data.Source; strings.HasPrefix(src, "http") &&
		!strings.Contains(src, "wallhaven.cc") && !strings.Contains(src, "whvn.cc") {
		c.InfoURL = src
	}
	return nil
}
