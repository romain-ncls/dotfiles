package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"math/rand/v2"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unicode"

	"github.com/godbus/dbus/v5"
)

// State is everything the daemon persists, in $XDG_DATA_HOME/backdrop/state.json.
type State struct {
	Model        Model      `json:"model"`
	Current      *Candidate `json:"current,omitempty"`
	CurrentSince time.Time  `json:"currentSince"`
	// Pool holds downloaded pictures waiting to be shown.
	Pool []*Candidate `json:"pool"`
	// Seen holds every candidate ever picked, so nothing is shown twice.
	Seen map[string]time.Time `json:"seen"`
	// Hashes catches the same picture under another ID.
	Hashes  []uint64          `json:"hashes"`
	Labels  map[string]string `json:"labels"` // candidate ID -> "like" | "dislike"
	TagIDs  map[string]int    `json:"tagIds"` // Wallhaven tags of labeled pictures
	History []HistoryEntry    `json:"history"`
}

type HistoryEntry struct {
	ID     string    `json:"id"`
	Title  string    `json:"title"`
	Source string    `json:"source"`
	Shown  time.Time `json:"shown"`
}

const (
	maxHashes  = 5000
	maxHistory = 200
	// Pool pictures older than this are dropped to keep the pool fresh.
	maxPoolAge = 7 * 24 * time.Hour
	// A pool picture scoring this far below the pool's best is practically
	// never drawn by the softmax, so it only takes up a slot.
	evictMargin = 3.0
)

// Info describes the current wallpaper to clients.
type Info struct {
	ID      string    `json:"id,omitempty"`
	Source  string    `json:"source,omitempty"`
	Title   string    `json:"title,omitempty"`
	Place   string    `json:"place,omitempty"`
	Credit  string    `json:"credit,omitempty"`
	InfoURL string    `json:"infoUrl,omitempty"`
	File    string    `json:"file,omitempty"`
	Liked   bool      `json:"liked"`
	Like    float64   `json:"like"` // predicted probability of a like
	Next    time.Time `json:"next"`
	Pool    int       `json:"pool"`
	// Pending is set when a change was asked with an empty pool: it happens
	// as soon as the next download completes.
	Pending bool `json:"pending"`
}

type Stats struct {
	Likes    int             `json:"likes"`
	Dislikes int             `json:"dislikes"`
	Pool     int             `json:"pool"`
	Sources  []SourceStats   `json:"sources"`
	Loved    []FeatureWeight `json:"loved"`
	Hated    []FeatureWeight `json:"hated"`
}

type SourceStats struct {
	Name     string  `json:"name"`
	Weight   float64 `json:"weight"`
	Learned  float64 `json:"learned"`
	Likes    int     `json:"likes"`
	Dislikes int     `json:"dislikes"`
}

type FeatureWeight struct {
	Name   string  `json:"name"`
	Weight float64 `json:"weight"`
	Count  int     `json:"count"`
}

type Daemon struct {
	cfg *Config
	dir string

	mu       sync.Mutex
	st       *State
	pending  bool // show the next committed picture right away
	failures int
	retryAt  time.Time

	refilling atomic.Bool
	wake      chan struct{}
}

func (d *Daemon) poolDir() string    { return filepath.Join(d.dir, "pool") }
func (d *Daemon) currentDir() string { return filepath.Join(d.dir, "current") }
func (d *Daemon) statePath() string  { return filepath.Join(d.dir, "state.json") }

// now drops the monotonic clock reading: it stops while the laptop sleeps,
// and rotation deadlines must count wall time.
func now() time.Time { return time.Now().Round(0) }

func runDaemon(configPath string) error {
	log.SetFlags(0)
	cfg, err := loadConfig(configPath)
	if err != nil {
		return err
	}
	d := &Daemon{cfg: cfg, dir: dataDir(), wake: make(chan struct{}, 1)}
	for _, dir := range []string{d.poolDir(), d.currentDir()} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}
	if d.st, err = loadState(d.statePath()); err != nil {
		return err
	}
	d.reconcile()

	ln, err := listen(socketPath())
	if err != nil {
		return err
	}
	srv := &http.Server{Handler: d.routes()}
	go srv.Serve(ln)
	defer os.Remove(socketPath())
	defer srv.Close()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	log.Printf("listening on %s, changing every %s, %d pictures in the pool", socketPath(), cfg.Interval, len(d.st.Pool))
	d.loop(ctx)

	d.mu.Lock()
	defer d.mu.Unlock()
	d.save()
	return nil
}

func listen(path string) (net.Listener, error) {
	if c, err := net.Dial("unix", path); err == nil {
		c.Close()
		return nil, fmt.Errorf("another daemon is listening on %s", path)
	}
	os.Remove(path)
	ln, err := net.Listen("unix", path)
	if err != nil {
		return nil, err
	}
	return ln, os.Chmod(path, 0o600)
}

func loadState(path string) (*State, error) {
	st := &State{}
	b, err := os.ReadFile(path)
	if err == nil {
		err = json.Unmarshal(b, st)
	}
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	if st.Model.Weights == nil {
		st.Model.Weights = map[string]float64{}
	}
	if st.Model.Counts == nil {
		st.Model.Counts = map[string]int{}
	}
	if st.Seen == nil {
		st.Seen = map[string]time.Time{}
	}
	if st.Labels == nil {
		st.Labels = map[string]string{}
	}
	if st.TagIDs == nil {
		st.TagIDs = map[string]int{}
	}
	return st, nil
}

// save writes the state atomically. Callers hold d.mu.
func (d *Daemon) save() {
	b, err := json.MarshalIndent(d.st, "", " ")
	if err == nil {
		tmp := d.statePath() + ".tmp"
		if err = os.WriteFile(tmp, b, 0o644); err == nil {
			err = os.Rename(tmp, d.statePath())
		}
	}
	if err != nil {
		log.Printf("saving state: %v", err)
	}
}

// reconcile drops state entries whose files are gone and files no entry
// refers to (e.g. an interrupted download).
func (d *Daemon) reconcile() {
	keep := map[string]bool{}
	d.st.Pool = slices.DeleteFunc(d.st.Pool, func(c *Candidate) bool {
		_, err := os.Stat(c.File)
		keep[c.File] = err == nil
		return err != nil
	})
	if entries, err := os.ReadDir(d.poolDir()); err == nil {
		for _, e := range entries {
			if p := filepath.Join(d.poolDir(), e.Name()); !keep[p] {
				os.Remove(p)
			}
		}
	}
	if c := d.st.Current; c != nil {
		if _, err := os.Stat(c.File); err != nil {
			d.st.Current = nil
		} else {
			d.clearCurrentDir(filepath.Base(c.File))
		}
	}
}

func (d *Daemon) kick() {
	select {
	case d.wake <- struct{}{}:
	default:
	}
}

func (d *Daemon) loop(ctx context.Context) {
	// A ticker rather than a timer set to the deadline: timers run on the
	// monotonic clock and would not count time spent suspended.
	tick := time.NewTicker(time.Minute)
	defer tick.Stop()
	for {
		d.mu.Lock()
		if d.st.Current == nil || time.Since(d.st.CurrentSince) >= d.cfg.Interval.Duration {
			d.advance()
		}
		d.mu.Unlock()
		d.maybeRefill(ctx)

		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		case <-d.wake:
		}
	}
}

func (d *Daemon) prior(source string) float64 {
	if w := d.cfg.Sources[source]; w > 0 {
		return math.Log(w)
	}
	return math.Inf(-1)
}

// score ranks candidates: the configured source prior plus the model's
// learned log-odds of a like.
func (d *Daemon) score(c *Candidate) float64 {
	return d.prior(c.Source) + d.st.Model.logit(c.features())
}

// advance puts the next picture from the pool on screen. With an empty pool
// it keeps the current one and marks the change as pending. Callers hold d.mu.
func (d *Daemon) advance() bool {
	if len(d.st.Pool) == 0 {
		d.pending = true
		return false
	}
	i := sample(d.st.Pool, d.score)
	next := d.st.Pool[i]
	d.st.Pool = slices.Delete(d.st.Pool, i, i+1)

	// The plugin shows the newest file of current/, which briefly holds both
	// the old and new picture.
	dst := filepath.Join(d.currentDir(), filepath.Base(next.File))
	t := time.Now()
	os.Chtimes(next.File, t, t)
	if err := os.Rename(next.File, dst); err != nil {
		log.Printf("showing %s: %v", next.ID, err)
		os.Remove(next.File)
		return d.advance()
	}
	next.File = dst
	d.clearCurrentDir(filepath.Base(dst))

	d.pending = false
	d.st.Current, d.st.CurrentSince = next, now()
	d.st.History = append(d.st.History, HistoryEntry{ID: next.ID, Title: next.Title, Source: next.Source, Shown: now()})
	if n := len(d.st.History); n > maxHistory {
		d.st.History = d.st.History[n-maxHistory:]
	}
	log.Printf("showing %s %q (predicted like %.0f%%, %d left in the pool)",
		next.ID, next.Title, 100*sigmoid(d.st.Model.logit(next.features())), len(d.st.Pool))
	d.save()
	d.kick() // top the pool up
	return true
}

func (d *Daemon) clearCurrentDir(keep string) {
	entries, _ := os.ReadDir(d.currentDir())
	for _, e := range entries {
		if e.Name() != keep {
			os.Remove(filepath.Join(d.currentDir(), e.Name()))
		}
	}
}

var errNoWallpaper = errors.New("no wallpaper yet, the daemon is still fetching")

func (d *Daemon) like() error {
	d.mu.Lock()
	defer d.mu.Unlock()
	c := d.st.Current
	if c == nil {
		return errNoWallpaper
	}
	if d.st.Labels[c.ID] == "like" {
		return nil
	}
	d.learn(c, "like")
	if err := copyFile(c.File, d.likedPath(c)); err != nil {
		log.Printf("saving liked picture: %v", err)
	}
	d.save()
	return nil
}

func (d *Daemon) dislike() error {
	d.mu.Lock()
	defer d.mu.Unlock()
	c := d.st.Current
	if c == nil {
		return errNoWallpaper
	}
	if d.st.Labels[c.ID] != "dislike" {
		if d.st.Labels[c.ID] == "like" {
			os.Remove(d.likedPath(c))
		}
		d.learn(c, "dislike")
	}
	d.save()
	d.advance()
	return nil
}

func (d *Daemon) next() error {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.advance()
	return nil
}

// learn records a label and trains the model on it. Callers hold d.mu.
func (d *Daemon) learn(c *Candidate, label string) {
	y := 0.0
	if label == "like" {
		y = 1
	}
	before := sigmoid(d.st.Model.logit(c.features()))
	d.st.Model.learn(c.features(), y)
	d.st.Labels[c.ID] = label
	for _, t := range c.Tags {
		d.st.TagIDs[t.Name] = t.ID
	}
	log.Printf("%sd %s %q (predicted %.0f%%, now %.0f%%)", label, c.ID, c.Title,
		100*before, 100*sigmoid(d.st.Model.logit(c.features())))
}

// likedPath names the liked copy after the title, e.g.
// "sailing-into-sunset-spotlight-128000000005956829.jpg".
func (d *Daemon) likedPath(c *Candidate) string {
	words := strings.FieldsFunc(strings.ToLower(c.Title), func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsDigit(r)
	})
	words = append(words[:min(8, len(words))], fileStem(c.ID))
	return filepath.Join(d.cfg.LikedDir, strings.Join(words, "-")+filepath.Ext(c.File))
}

func copyFile(src, dst string) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

// maybeRefill starts a background refill when the pool runs low.
func (d *Daemon) maybeRefill(ctx context.Context) {
	d.mu.Lock()
	d.prune()
	low := len(d.st.Pool) < d.cfg.PoolSize*2/3 || d.pending
	ready := time.Now().After(d.retryAt)
	d.mu.Unlock()
	if !low || !ready || !d.refilling.CompareAndSwap(false, true) {
		return
	}
	go func() {
		defer d.refilling.Store(false)
		added, err := d.refill(ctx)
		if err != nil && ctx.Err() == nil {
			log.Printf("refill: %v", err)
		}
		d.mu.Lock()
		defer d.mu.Unlock()
		if added > 0 {
			d.failures = 0
			return
		}
		// Offline, or sources returning only pictures already seen.
		d.failures++
		wait := min(time.Minute<<min(d.failures, 6), time.Hour)
		d.retryAt = time.Now().Add(wait)
		log.Printf("refill found nothing new, retrying in %s", wait)
	}()
}

// prune drops stale pool pictures and ones the model has since learned to
// rate far below the rest. Callers hold d.mu.
func (d *Daemon) prune() {
	best := math.Inf(-1)
	for _, c := range d.st.Pool {
		best = max(best, d.score(c))
	}
	d.st.Pool = slices.DeleteFunc(d.st.Pool, func(c *Candidate) bool {
		stale := time.Since(c.Added) > maxPoolAge
		unlikely := d.score(c) < best-evictMargin
		if stale || unlikely {
			os.Remove(c.File)
			log.Printf("dropping %s %q from the pool", c.ID, c.Title)
		}
		return stale || unlikely
	})
}

// refill tops the pool up: it lists candidates from the sources, keeps the
// ones the model rates best (with randomness, to keep exploring), and
// downloads and analyzes those. The network work runs without the lock.
func (d *Daemon) refill(ctx context.Context) (added int, err error) {
	d.mu.Lock()
	alloc := d.allocate(d.cfg.PoolSize - len(d.st.Pool))
	d.mu.Unlock()

	var errs []error
	for source, n := range alloc {
		listing, err := sources[source](ctx, d, n)
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", source, err))
		}
		d.mu.Lock()
		picked := d.pick(listing, n)
		d.mu.Unlock()

		for _, c := range picked {
			if ctx.Err() != nil {
				return added, ctx.Err()
			}
			if err := d.prepare(ctx, c); err != nil {
				log.Printf("skipping %s: %v", c.ID, err)
				d.mu.Lock()
				d.st.Seen[c.ID] = now()
				d.mu.Unlock()
				continue
			}
			if d.commit(c) {
				added++
			}
		}
	}
	return added, errors.Join(errs...)
}

// allocate splits n pool slots between sources, in proportion to their
// prior times learned preference, with a floor so none starves. Callers
// hold d.mu.
func (d *Daemon) allocate(n int) map[string]int {
	var names []string
	var weights []float64
	total := 0.0
	for name, w := range d.cfg.Sources {
		if w <= 0 || sources[name] == nil {
			continue
		}
		w *= math.Exp(d.st.Model.Weights["source:"+name])
		names = append(names, name)
		weights = append(weights, w)
		total += w
	}
	alloc := map[string]int{}
	for range n {
		r := rand.Float64()
		for i, w := range weights {
			if r -= 0.85*w/total + 0.15/float64(len(weights)); r <= 0 || i == len(weights)-1 {
				alloc[names[i]]++
				break
			}
		}
	}
	return alloc
}

// wallhavenQuery draws a search: one of the configured queries, or a tag
// that shows up in liked pictures. Callers hold d.mu.
func (d *Daemon) wallhavenQuery() string {
	queries := slices.Clone(d.cfg.Wallhaven.Queries)
	weights := make([]float64, len(queries))
	for i := range weights {
		weights[i] = 1
	}
	for name, id := range d.st.TagIDs {
		w := d.st.Model.Weights["tag:"+name]
		if w > 0.1 && d.st.Model.Counts["tag:"+name] >= 2 {
			queries = append(queries, fmt.Sprintf("id:%d", id))
			weights = append(weights, 10*w)
		}
	}
	if len(queries) == 0 {
		return ""
	}
	total := 0.0
	for _, w := range weights {
		total += w
	}
	r := rand.Float64() * total
	for i, w := range weights {
		if r -= w; r <= 0 {
			return queries[i]
		}
	}
	return queries[len(queries)-1]
}

// pick draws up to n unseen candidates from a listing. Callers hold d.mu.
func (d *Daemon) pick(listing []*Candidate, n int) []*Candidate {
	taken := map[string]bool{}
	for _, c := range d.st.Pool {
		taken[c.ID] = true
	}
	if d.st.Current != nil {
		taken[d.st.Current.ID] = true
	}
	var fresh []*Candidate
	for _, c := range listing {
		if _, seen := d.st.Seen[c.ID]; !seen && !taken[c.ID] {
			taken[c.ID] = true
			fresh = append(fresh, c)
		}
	}
	var out []*Candidate
	for len(out) < n && len(fresh) > 0 {
		i := sample(fresh, d.score)
		out = append(out, fresh[i])
		fresh = slices.Delete(fresh, i, i+1)
	}
	return out
}

// prepare downloads and analyzes a candidate.
func (d *Daemon) prepare(ctx context.Context, c *Candidate) error {
	switch {
	case c.Source == "wallhaven":
		if err := enrichWallhaven(ctx, c); err != nil {
			return err
		}
	case strings.HasPrefix(c.InfoURL, bingArchiveSite):
		// Only the credit is missing without it: not worth dropping the picture.
		if err := enrichBingArchive(ctx, c); err != nil {
			log.Printf("%s: %v", c.ID, err)
		}
	}
	file, err := download(ctx, c.ImageURL, d.poolDir(), fileStem(c.ID))
	if err != nil {
		return err
	}
	a, err := analyze(file)
	switch {
	case err != nil:
	case a.width < d.cfg.MinWidth || a.height < d.cfg.MinHeight:
		err = fmt.Errorf("too small (%dx%d)", a.width, a.height)
	case a.width*10 < a.height*13:
		err = fmt.Errorf("not landscape (%dx%d)", a.width, a.height)
	}
	if err != nil {
		os.Remove(file)
		return err
	}
	c.File, c.Visual, c.Hash, c.Added = file, a.features, a.hash, now()
	return nil
}

// commit adds a prepared candidate to the pool unless it duplicates a
// picture already seen.
func (d *Daemon) commit(c *Candidate) bool {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.st.Seen[c.ID] = now()
	for _, h := range d.st.Hashes {
		if similar(h, c.Hash) {
			log.Printf("skipping %s: duplicate of a picture already seen", c.ID)
			os.Remove(c.File)
			return false
		}
	}
	d.st.Hashes = append(d.st.Hashes, c.Hash)
	if n := len(d.st.Hashes); n > maxHashes {
		d.st.Hashes = d.st.Hashes[n-maxHashes:]
	}
	d.st.Pool = append(d.st.Pool, c)
	if d.pending {
		d.advance()
	}
	d.save()
	return true
}

// info describes the current wallpaper. Callers hold d.mu.
func (d *Daemon) info() Info {
	inf := Info{Pool: len(d.st.Pool), Pending: d.pending}
	if c := d.st.Current; c != nil {
		inf.ID, inf.Source, inf.Title, inf.Place, inf.Credit, inf.InfoURL, inf.File =
			c.ID, c.Source, c.Title, c.Place, c.Credit, c.InfoURL, c.File
		inf.Liked = d.st.Labels[c.ID] == "like"
		inf.Like = sigmoid(d.st.Model.logit(c.features()))
		inf.Next = d.st.CurrentSince.Add(d.cfg.Interval.Duration)
	}
	return inf
}

func (d *Daemon) stats() Stats {
	st := Stats{Pool: len(d.st.Pool)}
	perSource := map[string]*SourceStats{}
	for name, w := range d.cfg.Sources {
		perSource[name] = &SourceStats{Name: name, Weight: w, Learned: d.st.Model.Weights["source:"+name]}
	}
	for id, label := range d.st.Labels {
		source, _, _ := strings.Cut(id, ":")
		s := perSource[source]
		if s == nil {
			s = &SourceStats{Name: source}
			perSource[source] = s
		}
		if label == "like" {
			st.Likes++
			s.Likes++
		} else {
			st.Dislikes++
			s.Dislikes++
		}
	}
	for _, s := range perSource {
		st.Sources = append(st.Sources, *s)
	}
	sort.Slice(st.Sources, func(i, j int) bool { return st.Sources[i].Name < st.Sources[j].Name })

	var fs []FeatureWeight
	for name, w := range d.st.Model.Weights {
		if n := d.st.Model.Counts[name]; n >= 2 && name != "bias" && !strings.HasPrefix(name, "source:") {
			fs = append(fs, FeatureWeight{Name: name, Weight: w, Count: n})
		}
	}
	sort.Slice(fs, func(i, j int) bool { return fs[i].Weight > fs[j].Weight })
	for _, f := range fs[:min(12, len(fs))] {
		if f.Weight > 0.05 {
			st.Loved = append(st.Loved, f)
		}
	}
	for i := len(fs) - 1; i >= max(0, len(fs)-12); i-- {
		if fs[i].Weight < -0.05 {
			st.Hated = append(st.Hated, fs[i])
		}
	}
	return st
}

func (d *Daemon) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /current", func(w http.ResponseWriter, r *http.Request) {
		d.mu.Lock()
		defer d.mu.Unlock()
		writeJSON(w, d.info())
	})
	mux.HandleFunc("GET /stats", func(w http.ResponseWriter, r *http.Request) {
		d.mu.Lock()
		defer d.mu.Unlock()
		writeJSON(w, d.stats())
	})
	mux.HandleFunc("POST /like", d.action(d.like, func(Info) (string, string) {
		return "love", "Liked, more like this"
	}))
	mux.HandleFunc("POST /dislike", d.action(d.dislike, func(inf Info) (string, string) {
		if inf.Pending {
			return "dialog-cancel", "Disliked, fetching another one"
		}
		return "dialog-cancel", "Disliked, less like this"
	}))
	mux.HandleFunc("POST /next", d.action(d.next, nil))
	return mux
}

// action runs act and replies with the new current wallpaper. osd, if set,
// gives the Plasma OSD feedback to show: liking changes nothing on screen.
func (d *Daemon) action(act func() error, osd func(Info) (icon, text string)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := act(); err != nil {
			http.Error(w, err.Error(), http.StatusConflict)
			return
		}
		d.mu.Lock()
		inf := d.info()
		d.mu.Unlock()
		if osd != nil {
			go showOSD(osd(inf))
		}
		writeJSON(w, inf)
	}
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

func showOSD(icon, text string) {
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		return
	}
	defer conn.Close()
	conn.Object("org.kde.plasmashell", "/org/kde/osdService").Call("org.kde.osdService.showText", 0, icon, text)
}
