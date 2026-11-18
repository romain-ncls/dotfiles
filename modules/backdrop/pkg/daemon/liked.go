package main

import (
	"context"
	"errors"
	"log"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

// The liked folder is the lasting record of likes. state.json can be lost
// while the folder is kept: a reinstall that restores ~/Pictures but not
// ~/.local/share starts a blank model, and a picture liked before came back
// as new, rated as if never judged. So the daemon adopts the folder: every
// picture in it without a label is learned as a like and counted as seen.

// adoptRetry is how long adoption waits after failing to reach a source.
const adoptRetry = 10 * time.Minute

// likedFile is a picture of the liked folder the state has no label for.
type likedFile struct {
	path  string
	id    string
	title string     // the title words its name keeps
	known *Candidate // the same picture, on screen or in the pool
}

// likedID reads a candidate ID back from a liked copy's name (the inverse
// of likedPath): "gavin-o-donnell-digital-art-artwork-wallhaven-216zzg.jpg"
// is "wallhaven:216zzg", titled "gavin o donnell digital art artwork".
// Source IDs have no dash, so the last two words are the source and its ID.
func likedID(name string) (id, title string, ok bool) {
	if strings.HasPrefix(name, ".") {
		return "", "", false
	}
	words := strings.Split(strings.TrimSuffix(name, filepath.Ext(name)), "-")
	n := len(words)
	if n < 2 || sources[words[n-2]] == nil || words[n-1] == "" {
		return "", "", false
	}
	return words[n-2] + ":" + words[n-1], strings.Join(words[:n-2], " "), true
}

// maybeAdopt starts adopting the liked folder's unlabeled pictures, if
// there are any. It runs on every tick: listing the folder is cheap, and a
// picture put there by hand is picked up without a restart.
func (d *Daemon) maybeAdopt(ctx context.Context) {
	entries, err := os.ReadDir(d.cfg.LikedDir)
	if err != nil {
		return // no folder before the first like
	}
	var todo []likedFile
	d.mu.Lock()
	for _, e := range entries {
		id, title, ok := likedID(e.Name())
		if !ok || !e.Type().IsRegular() {
			continue
		}
		if _, labeled := d.st.Labels[id]; labeled {
			continue
		}
		l := likedFile{path: filepath.Join(d.cfg.LikedDir, e.Name()), id: id, title: title}
		if c := d.find(id); c != nil {
			cp := *c
			l.known = &cp
		}
		todo = append(todo, l)
	}
	ready := time.Now().After(d.adoptAt)
	d.mu.Unlock()
	if len(todo) == 0 || !ready || !d.adopting.CompareAndSwap(false, true) {
		return
	}

	go func() {
		defer d.adopting.Store(false)
		log.Printf("adopting %d pictures of %s the state has no label for", len(todo), d.cfg.LikedDir)
		offline := false
		for _, l := range todo {
			c, err := likedCandidate(ctx, l)
			if err != nil {
				offline = true
				continue
			}
			d.mu.Lock()
			if _, labeled := d.st.Labels[c.ID]; !labeled {
				d.adopt(c)
			}
			d.mu.Unlock()
		}
		if offline && ctx.Err() == nil {
			log.Printf("adopting liked pictures: a source is unreachable, retrying in %s", adoptRetry)
			d.mu.Lock()
			d.adoptAt = time.Now().Add(adoptRetry)
			d.mu.Unlock()
		}
	}()
}

// find returns the candidate with this ID on screen or in the pool.
// Callers hold d.mu.
func (d *Daemon) find(id string) *Candidate {
	if c := d.st.Current; c != nil && c.ID == id {
		return c
	}
	for _, c := range d.st.Pool {
		if c.ID == id {
			return c
		}
	}
	return nil
}

// likedCandidate describes a liked picture for the model. A picture on
// screen or in the pool is described already; otherwise its features are
// rebuilt as the source would have given them, from its name (Spotlight's
// title words, Bing's picture name) or Wallhaven's tags, and from its file.
// It fails only when Wallhaven cannot be reached: the picture is adopted
// on a later try, with its tags.
func likedCandidate(ctx context.Context, l likedFile) (*Candidate, error) {
	if l.known != nil {
		return l.known, nil
	}
	source, sid, _ := strings.Cut(l.id, ":")
	c := &Candidate{ID: l.id, Source: source, Title: l.title}
	switch source {
	case "wallhaven":
		if err := enrichWallhaven(ctx, c); err != nil {
			var ue *url.Error
			if errors.As(err, &ue) {
				return nil, err
			}
			// Gone from Wallhaven, say: the words of its name are left.
			log.Printf("%s: %v", c.ID, err)
			c.Words = keywords(c.Title)
		}
	case "bing":
		c.Words = nameWords(sid)
	default:
		c.Words = keywords(c.Title)
	}
	if a, err := analyze(l.path); err == nil {
		c.Visual, c.Hash = a.features, a.hash
	} else {
		log.Printf("%s: %v", l.path, err)
	}
	return c, nil
}

// adopt learns a liked picture the state did not know and counts it as
// seen, so it is not shown again from any source. Callers hold d.mu.
func (d *Daemon) adopt(c *Candidate) {
	d.learn(c, "like")
	if _, seen := d.st.Seen[c.ID]; !seen {
		d.st.Seen[c.ID] = now()
	}
	if c.Hash != 0 {
		d.remember(c.Hash)
	}
	d.st.Pool = slices.DeleteFunc(d.st.Pool, func(p *Candidate) bool {
		if p.ID == c.ID {
			os.Remove(p.File)
			return true
		}
		return false
	})
	d.save()
}
