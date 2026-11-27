// hdricc writes an ICC profile for KWin's HDR mode (colour profile source
// ICC): a display's real primaries, its SDR white and its peak, and an
// identity MHC2 tag, which makes KWin keep sending PQ BT.2020 unchanged.
// What KWin reads (src/core/iccprofile.cpp, src/backends/drm/drm_output.cpp,
// 6.8): the primaries (chrm, or the colorants adapted with chad) become the
// "native" gamut that SDR colour intensity stretches sRGB toward; lumi is the
// SDR white (and the max average); MHC2's peak is the max luminance.
//
// menadion's LG C6 (../home/.local/share/icc/): its EDID gives
// sRGB primaries, so KWin's own (EDID) profile leaves SDR colour intensity
// with nothing to stretch toward. The primaries are the ones the TV gives in
// its Dolby Vision block (edid-decode: "Unique Rx, Ry" ...), the peak is
// hdrcalibrator's, and the SDR white is 300 nits (docs/decisions.md):
//
//	go run . -red 0.6875,0.30859375 -green 0.24609375,0.7109375 \
//		-blue 0.1484375,0.046875 -sdr 300 -peak 1950 \
//		-name "LG C6 (HDR, native primaries)" \
//		-o ../home/.local/share/icc/lg-c6-sdr300-peak1950.icc
//
// The file's name carries its values: KWin reads a profile when its path
// changes, not when the file does (display.sh sets the path).
package main

import (
	"bytes"
	"encoding/binary"
	"flag"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
	"unicode/utf16"
)

type xy struct{ x, y float64 }
type vec [3]float64
type mat [3][3]float64

func (m mat) mul(n mat) (r mat) {
	for i := range 3 {
		for j := range 3 {
			for k := range 3 {
				r[i][j] += m[i][k] * n[k][j]
			}
		}
	}
	return
}

func (m mat) apply(v vec) (r vec) {
	for i := range 3 {
		for k := range 3 {
			r[i] += m[i][k] * v[k]
		}
	}
	return
}

func (m mat) inv() mat {
	a, b, c := m[0][0], m[0][1], m[0][2]
	d, e, f := m[1][0], m[1][1], m[1][2]
	g, h, i := m[2][0], m[2][1], m[2][2]
	det := a*(e*i-f*h) - b*(d*i-f*g) + c*(d*h-e*g)
	return mat{
		{(e*i - f*h) / det, (c*h - b*i) / det, (b*f - c*e) / det},
		{(f*g - d*i) / det, (a*i - c*g) / det, (c*d - a*f) / det},
		{(d*h - e*g) / det, (b*g - a*h) / det, (a*e - b*d) / det},
	}
}

func toXYZ(p xy) vec { return vec{p.x / p.y, 1, (1 - p.x - p.y) / p.y} }

// rgbToXYZ: the columns are the primaries' XYZ, scaled so RGB 1,1,1 is white (Y=1).
func rgbToXYZ(r, g, b, w xy) mat {
	R, G, B := toXYZ(r), toXYZ(g), toXYZ(b)
	m := mat{{R[0], G[0], B[0]}, {R[1], G[1], B[1]}, {R[2], G[2], B[2]}}
	s := m.inv().apply(toXYZ(w))
	for i := range 3 {
		for j := range 3 {
			m[i][j] *= s[j]
		}
	}
	return m
}

var bradford = mat{{0.8951, 0.2664, -0.1614}, {-0.7502, 1.7135, 0.0367}, {0.0389, -0.0685, 1.0296}}
var d50 = vec{0.9642, 1.0, 0.8249} // the ICC connection space's white

// adapt is the Bradford matrix from white src to white dst.
func adapt(src, dst vec) mat {
	s, d := bradford.apply(src), bradford.apply(dst)
	return bradford.inv().mul(mat{{d[0] / s[0], 0, 0}, {0, d[1] / s[1], 0}, {0, 0, d[2] / s[2]}}).mul(bradford)
}

type buf struct{ bytes.Buffer }

func (b *buf) u32(v uint32)  { binary.Write(b, binary.BigEndian, v) }
func (b *buf) u16(v uint16)  { binary.Write(b, binary.BigEndian, v) }
func (b *buf) s15(v float64) { b.u32(uint32(int32(math.Round(v * 65536)))) }
func (b *buf) sig(s string)  { b.WriteString(s) }

func mluc(s string) []byte {
	var b buf
	b.sig("mluc")
	b.u32(0)
	b.u32(1)  // records
	b.u32(12) // record size
	u := utf16.Encode([]rune(s))
	b.u16('e'<<8 | 'n')
	b.u16('U'<<8 | 'S')
	b.u32(uint32(2 * len(u)))
	b.u32(28) // the string's offset from the tag's start
	for _, c := range u {
		b.u16(c)
	}
	return b.Bytes()
}

func xyzTag(v vec) []byte {
	var b buf
	b.sig("XYZ ")
	b.u32(0)
	for _, c := range v {
		b.s15(c)
	}
	return b.Bytes()
}

func parseXY(s string) (xy, error) {
	a, b, ok := strings.Cut(s, ",")
	x, err1 := strconv.ParseFloat(a, 64)
	y, err2 := strconv.ParseFloat(b, 64)
	if !ok || err1 != nil || err2 != nil {
		return xy{}, fmt.Errorf("%q: want x,y", s)
	}
	return xy{x, y}, nil
}

func main() {
	red := flag.String("red", "", "red primary, x,y")
	green := flag.String("green", "", "green primary, x,y")
	blue := flag.String("blue", "", "blue primary, x,y")
	white := flag.String("white", "0.3127,0.3290", "white point, x,y (D65)")
	sdr := flag.Float64("sdr", 300, "SDR white in nits (lumi)")
	peak := flag.Float64("peak", 1000, "peak in nits (MHC2)")
	name := flag.String("name", "HDR display", "profile description")
	out := flag.String("o", "", "output file")
	flag.Parse()
	var p [4]xy
	for i, s := range []string{*red, *green, *blue, *white} {
		v, err := parseXY(s)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		p[i] = v
	}
	if *out == "" {
		fmt.Fprintln(os.Stderr, "-o is required")
		os.Exit(2)
	}

	wXYZ := toXYZ(p[3])
	chad := adapt(wXYZ, d50)
	m := chad.mul(rgbToXYZ(p[0], p[1], p[2], p[3])) // colorants in the D50 connection space

	tags := []struct {
		sig  string
		data []byte
	}{
		{"desc", mluc(*name)},
		{"cprt", mluc("No copyright, use freely")},
		{"wtpt", xyzTag(d50)}, // ICC v4: the media white is D50; chad holds the real one
	}
	{
		var b buf
		b.sig("sf32")
		b.u32(0)
		for i := range 3 {
			for j := range 3 {
				b.s15(chad[i][j])
			}
		}
		tags = append(tags, struct {
			sig  string
			data []byte
		}{"chad", b.Bytes()})
	}
	for j, s := range []string{"rXYZ", "gXYZ", "bXYZ"} {
		tags = append(tags, struct {
			sig  string
			data []byte
		}{s, xyzTag(vec{m[0][j], m[1][j], m[2][j]})})
	}
	var trc buf // gamma 2.2: KWin needs TRC tags to load a profile, MHC2 bypasses them
	trc.sig("curv")
	trc.u32(0)
	trc.u32(1)
	trc.u16(uint16(math.Round(2.2 * 256)))
	for _, s := range []string{"rTRC", "gTRC", "bTRC"} {
		tags = append(tags, struct {
			sig  string
			data []byte
		}{s, trc.Bytes()})
	}
	{
		var b buf
		b.sig("chrm")
		b.u32(0)
		b.u16(3)
		b.u16(0)
		for _, c := range p[:3] {
			b.u32(uint32(math.Round(c.x * 65536)))
			b.u32(uint32(math.Round(c.y * 65536)))
		}
		tags = append(tags, struct {
			sig  string
			data []byte
		}{"chrm", b.Bytes()})
	}
	tags = append(tags, struct {
		sig  string
		data []byte
	}{"lumi", xyzTag(vec{0, *sdr, 0})})
	{
		// MHC2 as KWin reads it: LUT size, min and max luminance, the offsets
		// of a 3x4 matrix (identity) and of the LUTs (none).
		var b buf
		b.sig("MHC2")
		b.u32(0)
		b.u32(0) // no LUT
		b.s15(0) // min luminance: keep the profile's black
		b.s15(*peak)
		b.u32(36) // matrix
		b.u32(0)
		b.u32(0)
		b.u32(0)
		for i := range 3 {
			for j := range 4 {
				v := 0.0
				if i == j {
					v = 1
				}
				b.s15(v)
			}
		}
		tags = append(tags, struct {
			sig  string
			data []byte
		}{"MHC2", b.Bytes()})
	}

	// layout: header, tag table, tag data (4-byte aligned)
	offset := 128 + 4 + 12*len(tags)
	var table, data buf
	table.u32(uint32(len(tags)))
	for _, t := range tags {
		for offset%4 != 0 {
			offset++
		}
		for data.Len() < offset-(128+4+12*len(tags)) {
			data.WriteByte(0)
		}
		table.sig(t.sig)
		table.u32(uint32(offset))
		table.u32(uint32(len(t.data)))
		data.Write(t.data)
		offset += len(t.data)
	}
	for data.Len()%4 != 0 {
		data.WriteByte(0)
	}
	size := 128 + table.Len() + data.Len()

	var h buf
	h.u32(uint32(size))
	h.u32(0)          // preferred CMM
	h.u32(0x04300000) // v4.3
	h.sig("mntr")
	h.sig("RGB ")
	h.sig("XYZ ")
	for _, v := range []uint16{2026, 11, 27, 0, 0, 0} {
		h.u16(v)
	}
	h.sig("acsp")
	h.u32(0)                 // platform
	h.u32(0)                 // flags
	h.u32(0)                 // manufacturer
	h.u32(0)                 // model
	h.Write(make([]byte, 8)) // attributes
	h.u32(0)                 // perceptual
	h.s15(d50[0])
	h.s15(d50[1])
	h.s15(d50[2])
	h.u32(0)                  // creator
	h.Write(make([]byte, 16)) // profile ID: not computed
	h.Write(make([]byte, 28))
	if h.Len() != 128 {
		panic(h.Len())
	}
	f := append(append(h.Bytes(), table.Bytes()...), data.Bytes()...)
	if err := os.WriteFile(*out, f, 0o644); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
