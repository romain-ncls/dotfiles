// Package yamledit adds entries to host.yaml and module.yaml files while
// keeping everything else as written, comments included. It works on block
// YAML indented by two spaces, the style of this repo's files.
package yamledit

import (
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"

	"github.com/goccy/go-yaml"
)

// SetKDEKey sets kde: file: group: key: value, creating what is missing.
func SetKDEKey(path, file string, group []string, key, value string) error {
	return edit(path, func(lines []string) []string {
		return setPath(lines, []string{"kde", file, strings.Join(group, "/"), key}, value)
	})
}

// AddToList appends item to the top-level list name (kde-ignore:), unless it
// is already there.
func AddToList(path, name, item string) error {
	return edit(path, func(lines []string) []string {
		start, end := block(lines, -1, 0, name)
		entry := "  - " + quote(item)
		if start < 0 {
			return appendBlock(lines, []string{name + ":", entry})
		}
		for _, l := range lines[start+1 : end] {
			if strings.TrimSpace(l) == strings.TrimSpace(entry) {
				return lines
			}
		}
		return insert(lines, lastContent(lines, start, end)+1, entry)
	})
}

func edit(path string, change func([]string) []string) error {
	data, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	text := strings.TrimRight(string(data), "\n")
	var lines []string
	if text != "" {
		lines = strings.Split(text, "\n")
	}
	out := strings.Join(change(lines), "\n") + "\n"
	var check any
	if err := yaml.Unmarshal([]byte(out), &check); err != nil {
		return fmt.Errorf("%s: the edit would break the YAML, nothing was written: %w", path, err)
	}
	return os.WriteFile(path, []byte(out), 0o644)
}

// setPath sets the scalar at the nested mapping path.
func setPath(lines []string, path []string, value string) []string {
	parent, end := -1, len(lines)
	for depth, name := range path {
		start, blockEnd := block(lines, parent, depth*2, name)
		last := depth == len(path)-1
		if start < 0 {
			// Create the rest of the path at the end of the parent's block.
			var add []string
			for d := depth; d < len(path); d++ {
				line := strings.Repeat("  ", d) + quote(path[d]) + ":"
				if d == len(path)-1 {
					line += " " + quote(value)
				}
				add = append(add, line)
			}
			if parent < 0 {
				return appendBlock(lines, add)
			}
			return insert(lines, lastContent(lines, parent, end)+1, add...)
		}
		if last {
			lines[start] = strings.Repeat("  ", depth) + quote(name) + ": " + quote(value) + trailingComment(lines[start])
			return lines
		}
		parent, end = start, blockEnd
	}
	return lines
}

var keyRE = regexp.MustCompile(`^( *)("(?:[^"\\]|\\.)*"|'(?:[^']|'')*'|[^#'"][^#]*?):(\s|$)`)

// block finds the key name at the given indent inside the parent's block
// (parent -1: the top level). It returns its line and the end of its block.
func block(lines []string, parent, indent int, name string) (start, end int) {
	from, to := 0, len(lines)
	if parent >= 0 {
		from = parent + 1
		to = blockEnd(lines, parent, indent-2)
	}
	for i := from; i < to; i++ {
		m := keyRE.FindStringSubmatch(lines[i])
		if m == nil || len(m[1]) != indent {
			continue
		}
		if unquote(m[2]) == name {
			return i, blockEnd(lines, i, indent)
		}
	}
	return -1, -1
}

// blockEnd returns where the block of the key at line i (with indent) ends:
// the next line with content at that indent or less (a "- " item at the
// same indent still belongs to it).
func blockEnd(lines []string, i, indent int) int {
	for j := i + 1; j < len(lines); j++ {
		l := lines[j]
		trimmed := strings.TrimLeft(l, " ")
		if strings.TrimSpace(l) == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		in := len(l) - len(trimmed)
		if in < indent || (in == indent && !strings.HasPrefix(trimmed, "- ")) {
			return j
		}
	}
	return len(lines)
}

// lastContent is the last non-blank line of a block.
func lastContent(lines []string, start, end int) int {
	last := start
	for j := start + 1; j < end && j < len(lines); j++ {
		if strings.TrimSpace(lines[j]) != "" {
			last = j
		}
	}
	return last
}

func insert(lines []string, at int, add ...string) []string {
	out := append([]string{}, lines[:at]...)
	out = append(out, add...)
	return append(out, lines[at:]...)
}

func appendBlock(lines []string, add []string) []string {
	if len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) != "" {
		lines = append(lines, "")
	}
	return append(lines, add...)
}

func trailingComment(line string) string {
	if i := strings.Index(line, " #"); i >= 0 && !strings.ContainsAny(line[:i], `"'`) {
		return line[i:]
	}
	return ""
}

var plain = regexp.MustCompile(`^[A-Za-z0-9_$.\/+@()~^=-][A-Za-z0-9_ $.\/+@()~^=,;\[\]&*!|>%-]*$`)

// quote writes s as a YAML scalar: plain when that reads back the same
// text, double-quoted otherwise.
func quote(s string) string {
	if s != "" && plain.MatchString(s) && !strings.Contains(s, ": ") && !strings.Contains(s, " #") &&
		strings.TrimSpace(s) == s && !strings.HasSuffix(s, ":") {
		return s
	}
	return strconv.Quote(s)
}

func unquote(s string) string {
	s = strings.TrimSpace(s)
	if strings.HasPrefix(s, `"`) {
		if u, err := strconv.Unquote(s); err == nil {
			return u
		}
	}
	if strings.HasPrefix(s, "'") && strings.HasSuffix(s, "'") && len(s) >= 2 {
		return strings.ReplaceAll(s[1:len(s)-1], "''", "'")
	}
	return s
}
