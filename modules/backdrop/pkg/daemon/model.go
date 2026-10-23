package main

import (
	"math"
	"math/rand/v2"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"
)

// Candidate is a picture from a source, in the pool or on screen.
type Candidate struct {
	ID       string `json:"id"` // "<source>:<source's id>"
	Source   string `json:"source"`
	Title    string `json:"title"`
	Place    string `json:"place,omitempty"`
	Credit   string `json:"credit,omitempty"`
	InfoURL  string `json:"infoUrl,omitempty"`
	ImageURL string `json:"imageUrl"`
	// Words are keywords from the title and description (or Wallhaven tags).
	Words []string `json:"words,omitempty"`
	Tags  []Tag    `json:"tags,omitempty"` // Wallhaven only
	// Visual holds the image's measured looks, see analyze.
	Visual []string  `json:"visual,omitempty"`
	Hash   uint64    `json:"hash,omitempty"`
	File   string    `json:"file,omitempty"`
	Added  time.Time `json:"added"`
}

type Tag struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

// features describes a candidate for the model. Each group (keywords, tags,
// looks) is scaled by 1/sqrt(n) so a long description does not outweigh the
// rest: one vote moves that picture's prediction by under 20 points.
//
// Keywords are shared across sources: liking Wallhaven's "mountains" also
// favors a Spotlight photo described with "mountains".
func (c *Candidate) features() map[string]float64 {
	f := map[string]float64{"bias": 1, "source:" + c.Source: 1}
	addGroup(f, "word:", c.Words)
	tags := make([]string, len(c.Tags))
	for i, t := range c.Tags {
		tags[i] = t.Name
	}
	addGroup(f, "tag:", tags)
	addGroup(f, "look:", c.Visual)
	return f
}

func addGroup(f map[string]float64, prefix string, items []string) {
	if len(items) == 0 {
		return
	}
	v := 1 / math.Sqrt(float64(len(items)))
	for _, it := range items {
		f[prefix+it] = v
	}
}

// Model is an online logistic regression of P(like | features), trained on
// likes (1) and dislikes (0).
type Model struct {
	Weights map[string]float64 `json:"weights"`
	Counts  map[string]int     `json:"counts"` // labels seen per feature
}

const (
	learningRate = 0.3
	l2           = 0.02
	// temperature of the softmax used to pick pictures: lower exploits the
	// model harder, higher explores more.
	temperature = 0.7
)

func (m *Model) logit(f map[string]float64) float64 {
	s := 0.0
	for k, v := range f {
		s += m.Weights[k] * v
	}
	return s
}

func (m *Model) learn(f map[string]float64, y float64) {
	g := y - sigmoid(m.logit(f))
	for k, v := range f {
		m.Weights[k] += learningRate * (g*v - l2*m.Weights[k])
		m.Counts[k]++
	}
}

func sigmoid(x float64) float64 { return 1 / (1 + math.Exp(-x)) }

// sample picks an index with probability softmax(score/temperature), so
// better rated pictures come first but everything keeps a chance.
func sample(cands []*Candidate, score func(*Candidate) float64) int {
	ws := make([]float64, len(cands))
	top := math.Inf(-1)
	for i, c := range cands {
		ws[i] = score(c) / temperature
		top = max(top, ws[i])
	}
	total := 0.0
	for i := range ws {
		ws[i] = math.Exp(ws[i] - top)
		total += ws[i]
	}
	r := rand.Float64() * total
	for i, w := range ws {
		if r -= w; r <= 0 {
			return i
		}
	}
	return len(ws) - 1
}

var wordRe = regexp.MustCompile(`\p{L}+`)

// keywords extracts up to 40 distinct content words, lightly stemmed.
func keywords(texts ...string) []string {
	seen := map[string]bool{}
	var out []string
	for _, t := range texts {
		for _, w := range wordRe.FindAllString(strings.ToLower(t), -1) {
			if utf8.RuneCountInString(w) < 3 || stopwords[w] {
				continue
			}
			w = stem(w)
			if seen[w] {
				continue
			}
			seen[w] = true
			out = append(out, w)
			if len(out) == 40 {
				return out
			}
		}
	}
	return out
}

// stem folds plurals so "mountains" and "mountain" are one feature.
func stem(w string) string {
	switch {
	case strings.HasSuffix(w, "ies") && len(w) > 4:
		return w[:len(w)-3] + "y"
	case strings.HasSuffix(w, "ss"), strings.HasSuffix(w, "us"), strings.HasSuffix(w, "is"):
		return w
	case strings.HasSuffix(w, "s") && len(w) > 3:
		return w[:len(w)-1]
	}
	return w
}

var stopwords = func() map[string]bool {
	m := map[string]bool{}
	for _, w := range strings.Fields(`
		the and for are but not you your yours our ours their theirs they them this that these those
		its it's has have had was were been being with from into onto over under upon about above below
		than then there here where when what which while who whom whose why how all any both each few
		more most other others some such only own same too very can could would should will may might
		must shall just also even still yet though although however because since until after before
		during through between among along across around behind beyond within without against toward
		towards off out per via like make made makes know known take taken get gets got come came see
		seen look looks way ways year years day days time times today world part parts called name
		named first new old long well back much many lot lots one two three her his him she himself
		herself itself themselves itself whether either neither every another something anything
		nothing everything someone anyone everyone thing things kind sort place places here's there's
		photo photos photograph image images picture pictures getty shutterstock alamy stock moment
		credit learn click right left wallhaven quite rather really almost often ever never always
		perhaps maybe enough become became becomes seem seems seemed let lets use used using
	`) {
		m[w] = true
	}
	return m
}()
