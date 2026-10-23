package main

import (
	"bufio"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"math"
	"math/bits"
	"os"
)

// analysis is what the model sees of a picture's looks. Metadata alone says
// little about why a picture is ugly; washed-out, dim or cluttered images
// are what the look features let it learn.
type analysis struct {
	width, height int
	hash          uint64
	features      []string

	brightness, contrast, saturation, detail, chroma float64
}

// The image is sampled on a coarse grid: plenty for global statistics and
// fast even on 4K JPEGs.
const gridW, gridH = 96, 54

func analyze(path string) (*analysis, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	img, _, err := image.Decode(bufio.NewReader(f))
	if err != nil {
		return nil, err
	}
	b := img.Bounds()
	a := &analysis{width: b.Dx(), height: b.Dy()}

	var lum [gridH][gridW]float64
	var sumL, sumL2, sumS, sumC float64
	var hueMass [len(hueNames)]float64
	for gy := range gridH {
		for gx := range gridW {
			r, g, bl := cellColor(img, b, gx, gy)
			l := 0.299*r + 0.587*g + 0.114*bl
			lum[gy][gx] = l
			sumL += l
			sumL2 += l * l
			hi, lo := max(r, g, bl), min(r, g, bl)
			c := hi - lo
			if hi > 0 {
				sumS += c / hi
			}
			sumC += c
			if c > 0.05 {
				hueMass[hueIndex(r, g, bl, hi, c)] += c
			}
		}
	}
	n := float64(gridW * gridH)
	a.brightness = sumL / n
	a.contrast = math.Sqrt(max(0, sumL2/n-a.brightness*a.brightness))
	a.saturation = sumS / n
	a.chroma = sumC / n

	var grad float64
	for y := range gridH - 1 {
		for x := range gridW - 1 {
			grad += math.Abs(lum[y][x+1]-lum[y][x]) + math.Abs(lum[y+1][x]-lum[y][x])
		}
	}
	a.detail = grad / float64((gridW-1)*(gridH-1))

	hue := "neutral"
	if a.chroma > 0.08 {
		best := 0
		for i, m := range hueMass {
			if m > hueMass[best] {
				best = i
			}
		}
		hue = hueNames[best]
	}

	a.hash = dhash(&lum)
	a.features = []string{
		"brightness=" + level(a.brightness, []float64{0.22, 0.33, 0.45, 0.6}, "very dark", "dark", "medium", "bright", "very bright"),
		"contrast=" + level(a.contrast, []float64{0.14, 0.2, 0.26}, "flat", "soft", "strong", "harsh"),
		"saturation=" + level(a.saturation, []float64{0.2, 0.35, 0.5}, "muted", "natural", "vivid", "intense"),
		"detail=" + level(a.detail, []float64{0.045, 0.065, 0.1}, "minimal", "calm", "detailed", "busy"),
		"hue=" + hue,
	}
	return a, nil
}

// cellColor averages 3x3 samples spread over grid cell (gx, gy).
func cellColor(img image.Image, b image.Rectangle, gx, gy int) (r, g, bl float64) {
	const k = 3
	for sy := range k {
		for sx := range k {
			x := b.Min.X + ((gx*k+sx)*2+1)*b.Dx()/(gridW*k*2)
			y := b.Min.Y + ((gy*k+sy)*2+1)*b.Dy()/(gridH*k*2)
			cr, cg, cb, _ := img.At(x, y).RGBA()
			r += float64(cr)
			g += float64(cg)
			bl += float64(cb)
		}
	}
	const scale = k * k * 0xffff
	return r / scale, g / scale, bl / scale
}

// Hue ranges in degrees, split along perceived color names rather than
// evenly: sunsets should land in one bin, not straddle two.
var (
	hueNames = [...]string{"red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink"}
	hueEnds  = [...]float64{15, 45, 70, 165, 200, 255, 290, 345}
)

func hueIndex(r, g, b, hi, c float64) int {
	var h float64
	switch hi {
	case r:
		h = math.Mod((g-b)/c, 6)
	case g:
		h = (b-r)/c + 2
	default:
		h = (r-g)/c + 4
	}
	deg := h * 60
	if deg < 0 {
		deg += 360
	}
	for i, end := range hueEnds {
		if deg < end {
			return i
		}
	}
	return 0 // 345-360 wraps back to red
}

func level(v float64, cuts []float64, names ...string) string {
	for i, c := range cuts {
		if v < c {
			return names[i]
		}
	}
	return names[len(cuts)]
}

// dhash is a 64-bit difference hash: near-identical pictures (the same photo
// from Bing and Spotlight, or at another resolution) differ by a few bits.
func dhash(lum *[gridH][gridW]float64) uint64 {
	var cells [8][9]float64
	for y := range 8 {
		for x := range 9 {
			y0, y1 := y*gridH/8, (y+1)*gridH/8
			x0, x1 := x*gridW/9, (x+1)*gridW/9
			s := 0.0
			for yy := y0; yy < y1; yy++ {
				for xx := x0; xx < x1; xx++ {
					s += lum[yy][xx]
				}
			}
			cells[y][x] = s / float64((y1-y0)*(x1-x0))
		}
	}
	var h uint64
	for y := range 8 {
		for x := range 8 {
			h <<= 1
			if cells[y][x] < cells[y][x+1] {
				h |= 1
			}
		}
	}
	return h
}

func similar(a, b uint64) bool { return bits.OnesCount64(a^b) <= 8 }
