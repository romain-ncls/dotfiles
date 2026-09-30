package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Config is read from the --config JSON file on top of defaultConfig, so a
// file only needs the settings it changes. Maps merge key by key: setting
// {"sources": {"bing": 0}} disables Bing and keeps the other sources.
type Config struct {
	// Interval between scheduled wallpaper changes.
	Interval duration `json:"interval"`
	// PoolSize is how many downloaded pictures the daemon keeps ready.
	PoolSize int `json:"poolSize"`
	// Pictures smaller than this are skipped.
	MinWidth  int `json:"minWidth"`
	MinHeight int `json:"minHeight"`
	// Market is the locale of Spotlight's texts. Keywords are learned from
	// them, so keep it stable once the model has been trained.
	Market  string `json:"market"`
	Country string `json:"country"`
	Bing    struct {
		// Market is the Bing edition. France gets fr-FR, which is also what
		// KDE's Picture of the Day showed.
		Market string `json:"market"`
		// Archive is the bingwallpaper.anerg.com edition used as back
		// catalog, "" to use Bing's two-week feed only.
		Archive string `json:"archive"`
	} `json:"bing"`
	// Sources maps a source name to its prior weight. The learned preference
	// adjusts it; 0 disables the source.
	Sources   map[string]float64 `json:"sources"`
	Wallhaven struct {
		// Queries are the base searches. Tags from liked pictures are added
		// to them over time.
		Queries []string `json:"queries"`
		// Categories is Wallhaven's general/anime/people bit mask.
		Categories string `json:"categories"`
	} `json:"wallhaven"`
	// LikedDir receives a copy of every liked picture.
	LikedDir string `json:"likedDir"`
}

func defaultConfig() *Config {
	c := &Config{
		Interval:  duration{4 * time.Hour},
		PoolSize:  12,
		MinWidth:  1920,
		MinHeight: 1080,
		Market:    "en-US",
		Country:   "FR",
		Sources:   map[string]float64{"spotlight": 1, "wallhaven": 1, "bing": 1},
	}
	c.Bing.Market = "fr-FR"
	c.Bing.Archive = "fr"
	c.Wallhaven.Queries = []string{"digital art", "concept art", "fantasy art", "illustration", "science fiction", "digital painting"}
	c.Wallhaven.Categories = "100"
	return c
}

func loadConfig(path string) (*Config, error) {
	c := defaultConfig()
	if path != "" {
		b, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		if err := json.Unmarshal(b, c); err != nil {
			return nil, fmt.Errorf("%s: %w", path, err)
		}
	}
	if c.LikedDir == "" {
		c.LikedDir = filepath.Join(picturesDir(), "Backdrop")
	}
	c.PoolSize = max(c.PoolSize, 3)
	return c, nil
}

// picturesDir returns XDG_PICTURES_DIR from user-dirs.dirs.
func picturesDir() string {
	home, _ := os.UserHomeDir()
	configHome := os.Getenv("XDG_CONFIG_HOME")
	if configHome == "" {
		configHome = filepath.Join(home, ".config")
	}
	if b, err := os.ReadFile(filepath.Join(configHome, "user-dirs.dirs")); err == nil {
		for _, line := range strings.Split(string(b), "\n") {
			if v, ok := strings.CutPrefix(line, "XDG_PICTURES_DIR="); ok {
				return strings.ReplaceAll(strings.Trim(v, `"`), "$HOME", home)
			}
		}
	}
	return filepath.Join(home, "Pictures")
}

// duration reads Go duration strings such as "4h" or "90m".
type duration struct{ time.Duration }

func (d *duration) UnmarshalJSON(b []byte) error {
	var s string
	if err := json.Unmarshal(b, &s); err != nil {
		return err
	}
	v, err := time.ParseDuration(s)
	if err != nil {
		return err
	}
	if v < time.Minute {
		return fmt.Errorf("interval %s is shorter than a minute", s)
	}
	d.Duration = v
	return nil
}
