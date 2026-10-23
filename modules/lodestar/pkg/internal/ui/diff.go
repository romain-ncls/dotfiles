package ui

import (
	"bytes"
	"fmt"
	"strings"
)

type edit struct {
	op   byte // ' ', '-', '+'
	text string
}

// maxDiff bounds the work of a diff; bigger changes are summed up instead.
const maxDiff = 2000

// Diff returns a unified diff of old and new with 3 lines of context, or a
// one-line summary when the content is binary or too different.
func Diff(old, new []byte) string {
	if bytes.IndexByte(old, 0) >= 0 || bytes.IndexByte(new, 0) >= 0 {
		return "binary content differs"
	}
	a, b := splitLines(old), splitLines(new)
	edits, ok := myers(a, b)
	if !ok {
		return fmt.Sprintf("%d lines → %d lines (too different to show)", len(a), len(b))
	}
	return hunks(edits, 3)
}

func splitLines(b []byte) []string {
	if len(b) == 0 {
		return nil
	}
	s := string(b)
	noEOL := !strings.HasSuffix(s, "\n")
	lines := strings.Split(strings.TrimSuffix(s, "\n"), "\n")
	if noEOL {
		lines[len(lines)-1] += " ⏎ (no newline at end)"
	}
	return lines
}

// myers is the O((N+M)D) diff of Myers (1986), giving up past maxDiff edits.
func myers(a, b []string) ([]edit, bool) {
	n, m := len(a), len(b)
	max := n + m
	if max == 0 {
		return nil, true
	}
	off := max + 1
	v := make([]int, 2*max+3)
	var trace [][]int
	for d := 0; d <= max; d++ {
		if d > maxDiff {
			return nil, false
		}
		trace = append(trace, append([]int(nil), v...))
		for k := -d; k <= d; k += 2 {
			var x int
			if k == -d || (k != d && v[off+k-1] < v[off+k+1]) {
				x = v[off+k+1]
			} else {
				x = v[off+k-1] + 1
			}
			y := x - k
			for x < n && y < m && a[x] == b[y] {
				x, y = x+1, y+1
			}
			v[off+k] = x
			if x >= n && y >= m {
				return backtrack(trace, a, b, off), true
			}
		}
	}
	return nil, false
}

func backtrack(trace [][]int, a, b []string, off int) []edit {
	var out []edit
	x, y := len(a), len(b)
	for d := len(trace) - 1; d >= 0; d-- {
		v := trace[d]
		k := x - y
		var prevK int
		if k == -d || (k != d && v[off+k-1] < v[off+k+1]) {
			prevK = k + 1
		} else {
			prevK = k - 1
		}
		prevX := v[off+prevK]
		prevY := prevX - prevK
		for x > prevX && y > prevY {
			out = append(out, edit{' ', a[x-1]})
			x, y = x-1, y-1
		}
		if d > 0 {
			if x == prevX {
				out = append(out, edit{'+', b[y-1]})
			} else {
				out = append(out, edit{'-', a[x-1]})
			}
		}
		x, y = prevX, prevY
	}
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	return out
}

// hunks formats edits as unified-diff hunks.
func hunks(edits []edit, context int) string {
	var sb strings.Builder
	n := len(edits)
	for i := 0; i < n; {
		if edits[i].op == ' ' {
			i++
			continue
		}
		start := max(i-context, 0)
		end := i
		for end < n {
			if edits[end].op != ' ' {
				end++
				continue
			}
			run := end
			for run < n && edits[run].op == ' ' {
				run++
			}
			if run == n || run-end > 2*context {
				end = min(end+context, n)
				break
			}
			end = run
		}
		oldLine, newLine := 1, 1
		for _, e := range edits[:start] {
			if e.op != '+' {
				oldLine++
			}
			if e.op != '-' {
				newLine++
			}
		}
		var oldN, newN int
		for _, e := range edits[start:end] {
			if e.op != '+' {
				oldN++
			}
			if e.op != '-' {
				newN++
			}
		}
		if oldN == 0 { // unified diff numbers an empty range from the line before
			oldLine--
		}
		if newN == 0 {
			newLine--
		}
		fmt.Fprintf(&sb, "@@ -%d,%d +%d,%d @@\n", oldLine, oldN, newLine, newN)
		for _, e := range edits[start:end] {
			sb.WriteByte(e.op)
			sb.WriteString(e.text)
			sb.WriteByte('\n')
		}
		i = end
	}
	return sb.String()
}
