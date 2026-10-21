// Package kconfig reads KDE's config files (KConfig INI), and rewrites whole
// groups while keeping every other line as it was.
package kconfig

import (
	"bytes"
	"errors"
	"io/fs"
	"os"
	"sort"
	"strconv"
	"strings"
)

// File is a parsed KConfig file.
type File struct {
	Groups []*Group
}

// Group is a [A][B] section. The first group of a file may have no path:
// keys before any header.
type Group struct {
	Path   []string
	Header string // as written, e.g. [Group][$i]; empty for a new group
	Lines  []Line
}

// Line is one line of a group: an entry, or anything else kept verbatim.
type Line struct {
	Raw      string
	Key      string // with its locale suffix ([fr]) but without flags ([$e])
	Value    string // unescaped
	RawValue string // as written in the file, escapes included
	Entry    bool
}

// Read parses the file at path; a missing file is empty.
func Read(path string) (*File, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return &File{}, nil
	}
	if err != nil {
		return nil, err
	}
	return Parse(data), nil
}

// Parse parses KConfig text.
func Parse(data []byte) *File {
	f := &File{}
	cur := &Group{}
	f.Groups = append(f.Groups, cur)
	for _, raw := range strings.Split(strings.TrimSuffix(string(data), "\n"), "\n") {
		line := strings.TrimSpace(raw)
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			cur = &Group{Path: parseHeader(line), Header: line}
			f.Groups = append(f.Groups, cur)
			continue
		}
		l := Line{Raw: raw}
		if k, v, ok := strings.Cut(line, "="); ok && line != "" && !strings.HasPrefix(line, "#") {
			l.Entry = true
			l.Key = stripFlags(strings.TrimSpace(k))
			l.RawValue = strings.TrimSpace(v)
			l.Value = Unescape(l.RawValue)
		}
		cur.Lines = append(cur.Lines, l)
	}
	if len(f.Groups[0].Lines) == 0 {
		f.Groups = f.Groups[1:]
	}
	return f
}

// parseHeader splits [A][B][$i] into A, B: the immutable flag is dropped,
// special groups like [$Version] keep their name.
func parseHeader(h string) []string {
	var path []string
	for _, part := range strings.Split(h[1:len(h)-1], "][") {
		if part == "$i" {
			continue
		}
		path = append(path, part)
	}
	return path
}

// stripFlags removes [$e]-style flags from a key, keeping a locale ([fr]).
func stripFlags(k string) string {
	for {
		i := strings.Index(k, "[$")
		if i < 0 {
			return k
		}
		j := strings.Index(k[i:], "]")
		if j < 0 {
			return k
		}
		k = k[:i] + k[i+j+1:]
	}
}

// Unescape decodes KConfig's escapes: \\ \n \t \r \s \xHH.
func Unescape(v string) string {
	if !strings.Contains(v, `\`) {
		return v
	}
	var sb strings.Builder
	for i := 0; i < len(v); i++ {
		if v[i] != '\\' || i+1 == len(v) {
			sb.WriteByte(v[i])
			continue
		}
		i++
		switch v[i] {
		case '\\':
			sb.WriteByte('\\')
		case 'n':
			sb.WriteByte('\n')
		case 't':
			sb.WriteByte('\t')
		case 'r':
			sb.WriteByte('\r')
		case 's':
			sb.WriteByte(' ')
		case 'x':
			if i+2 < len(v) {
				if b, err := strconv.ParseUint(v[i+1:i+3], 16, 8); err == nil {
					sb.WriteByte(byte(b))
					i += 2
					continue
				}
			}
			sb.WriteString(`\x`)
		default:
			sb.WriteByte('\\')
			sb.WriteByte(v[i])
		}
	}
	return sb.String()
}

// Escape encodes a value the way KConfig writes it.
func Escape(v string) string {
	var sb strings.Builder
	for i := 0; i < len(v); i++ {
		switch c := v[i]; {
		case c == '\\':
			sb.WriteString(`\\`)
		case c == '\n':
			sb.WriteString(`\n`)
		case c == '\t':
			sb.WriteString(`\t`)
		case c == '\r':
			sb.WriteString(`\r`)
		case c == ' ' && (i == 0 || i == len(v)-1):
			sb.WriteString(`\s`)
		case c < 0x20:
			sb.WriteString(`\x` + strconv.FormatUint(uint64(c), 16))
		default:
			sb.WriteByte(c)
		}
	}
	return sb.String()
}

func samePath(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// Group returns the group at path, or nil.
func (f *File) Group(path []string) *Group {
	for _, g := range f.Groups {
		if samePath(g.Path, path) {
			return g
		}
	}
	return nil
}

// Get returns a key's value in a group.
func (f *File) Get(path []string, key string) (string, bool) {
	if g := f.Group(path); g != nil {
		return g.Get(key)
	}
	return "", false
}

// Get returns a key's value; the last occurrence wins, as in KConfig.
func (g *Group) Get(key string) (string, bool) {
	val, found := "", false
	for _, l := range g.Lines {
		if l.Entry && l.Key == key {
			val, found = l.Value, true
		}
	}
	return val, found
}

// Map returns the group's entries.
func (g *Group) Map() map[string]string {
	m := map[string]string{}
	for _, l := range g.Lines {
		if l.Entry {
			m[l.Key] = l.Value
		}
	}
	return m
}

// RawEntries returns every key as "group/…/key" -> value as written in the
// file (escaped: binary values stay text).
func (f *File) RawEntries() map[string]string {
	out := map[string]string{}
	for _, g := range f.Groups {
		prefix := strings.Join(g.Path, "/")
		for _, l := range g.Lines {
			if l.Entry {
				out[prefix+"/"+l.Key] = l.RawValue
			}
		}
	}
	return out
}

// SetGroup replaces the group's lines with keys (sorted), or appends the
// group at the end.
func (f *File) SetGroup(path []string, keys map[string]string) {
	names := make([]string, 0, len(keys))
	for k := range keys {
		names = append(names, k)
	}
	sort.Strings(names)
	var lines []Line
	for _, k := range names {
		lines = append(lines, Line{Raw: k + "=" + Escape(keys[k]), Key: k, Value: keys[k], RawValue: Escape(keys[k]), Entry: true})
	}
	if g := f.Group(path); g != nil {
		g.Lines = lines
		return
	}
	f.Groups = append(f.Groups, &Group{Path: path, Lines: lines})
}

// DeleteGroups removes every group for which drop returns true.
func (f *File) DeleteGroups(drop func(path []string) bool) {
	keep := f.Groups[:0]
	for _, g := range f.Groups {
		if !drop(g.Path) {
			keep = append(keep, g)
		}
	}
	f.Groups = keep
}

// Bytes formats the file: groups separated by a blank line.
func (f *File) Bytes() []byte {
	var buf bytes.Buffer
	for i, g := range f.Groups {
		if i > 0 && buf.Len() > 0 {
			buf.WriteByte('\n')
		}
		switch {
		case g.Header != "":
			buf.WriteString(g.Header + "\n")
		case len(g.Path) > 0:
			buf.WriteString("[" + strings.Join(g.Path, "][") + "]\n")
		}
		lines := g.Lines
		for len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1].Raw) == "" {
			lines = lines[:len(lines)-1]
		}
		for _, l := range lines {
			buf.WriteString(l.Raw + "\n")
		}
	}
	return buf.Bytes()
}
