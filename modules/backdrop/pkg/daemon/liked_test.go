package main

import (
	"context"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestLikedIDReadsLikedPath(t *testing.T) {
	d := &Daemon{cfg: &Config{LikedDir: "/liked"}}
	for _, tc := range []struct{ id, title, wantTitle string }{
		{"wallhaven:216zzg", "gavin o'donnell · digital art · artwork", "gavin o donnell digital art artwork"},
		{"spotlight:128000000005953009", "Light on the lake", "light on the lake"},
		{"bing:LakeTahoeRock", "Bonsai Rock, lac Tahoe, États-Unis", "bonsai rock lac tahoe états unis"},
		{"bing:Banff24", "", ""},
	} {
		c := &Candidate{ID: tc.id, Title: tc.title, File: "/pool/x.jpg"}
		name := filepath.Base(d.likedPath(c))
		id, title, ok := likedID(name)
		if !ok || id != tc.id || title != tc.wantTitle {
			t.Errorf("likedID(%q) = %q, %q, %v; want %q, %q", name, id, title, ok, tc.id, tc.wantTitle)
		}
	}
	for _, name := range []string{"holiday.jpg", ".download-123", "x-flickr-123.jpg", "wallhaven-.jpg"} {
		if id, _, ok := likedID(name); ok {
			t.Errorf("likedID(%q) = %q, want no ID", name, id)
		}
	}
}

func TestAdoptLikedFolder(t *testing.T) {
	liked, data := t.TempDir(), t.TempDir()
	st, err := loadState(filepath.Join(data, "state.json"))
	if err != nil {
		t.Fatal(err)
	}
	d := &Daemon{cfg: &Config{LikedDir: liked}, dir: data, st: st, wake: make(chan struct{}, 1)}

	// On screen, with the tags the folder's name would not give.
	d.st.Current = &Candidate{ID: "spotlight:1", Source: "spotlight", Title: "Light on the lake",
		Words: []string{"light", "lake", "norway"}}
	d.st.Seen["spotlight:1"] = time.Now()
	writePicture(t, filepath.Join(liked, "light-on-the-lake-spotlight-1.png"), 0)
	// Known from the folder only.
	writePicture(t, filepath.Join(liked, "bonsai-rock-lac-tahoe-bing-LakeTahoeRock.png"), 1)
	// Judged since: the state's label stands.
	writePicture(t, filepath.Join(liked, "dunes-spotlight-2.png"), 2)
	d.st.Labels["spotlight:2"] = "dislike"
	// Not Backdrop's.
	writePicture(t, filepath.Join(liked, "holiday.png"), 3)

	d.maybeAdopt(context.Background())
	for deadline := time.Now().Add(10 * time.Second); d.adopting.Load(); {
		if time.Now().After(deadline) {
			t.Fatal("adoption did not finish")
		}
		time.Sleep(10 * time.Millisecond)
	}

	want := map[string]string{"spotlight:1": "like", "bing:LakeTahoeRock": "like", "spotlight:2": "dislike"}
	if len(d.st.Labels) != len(want) {
		t.Errorf("labels = %v, want %v", d.st.Labels, want)
	}
	for id, label := range want {
		if d.st.Labels[id] != label {
			t.Errorf("label of %s = %q, want %q", id, d.st.Labels[id], label)
		}
	}
	if _, seen := d.st.Seen["bing:LakeTahoeRock"]; !seen {
		t.Error("an adopted picture is not counted as seen")
	}
	if len(d.st.Hashes) != 1 {
		t.Errorf("%d hashes recorded, want the folder-only picture's", len(d.st.Hashes))
	}
	for _, f := range []string{"word:norway", "word:tahoe", "source:bing"} {
		if d.st.Model.Weights[f] <= 0 {
			t.Errorf("feature %s not learned as liked (weight %v)", f, d.st.Model.Weights[f])
		}
	}
	if inf := d.info(); !inf.Liked {
		t.Error("the picture on screen, in the liked folder, is not shown as liked")
	}
	if _, err := os.Stat(d.statePath()); err != nil {
		t.Errorf("state not saved: %v", err)
	}
}

// writePicture writes a small PNG, a different pattern for each n.
func writePicture(t *testing.T, path string, n int) {
	img := image.NewRGBA(image.Rect(0, 0, 192, 108))
	for y := range 108 {
		for x := range 192 {
			v := uint8((x*(n+1) + y*(3-n)*2) % 256)
			img.Set(x, y, color.RGBA{v, uint8(255 - int(v)), uint8(n * 60), 255})
		}
	}
	f, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if err := png.Encode(f, img); err != nil {
		t.Fatal(err)
	}
}
