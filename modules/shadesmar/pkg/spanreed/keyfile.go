package main

import "strings"

// keyfile: a GLib key file (the VPN plugins' .name files, their auth
// dialogs' answers), its groups in order. Localized keys (Label[fr]) are
// left out: the dialogs run in English, as the shell is.
type keyfile []group

type group struct {
	name string
	keys map[string]string
}

func parseKeyfile(s string) keyfile {
	var k keyfile
	for _, line := range strings.Split(s, "\n") {
		line = strings.TrimSpace(line)
		switch {
		case line == "" || line[0] == '#':
		case line[0] == '[' && line[len(line)-1] == ']':
			k = append(k, group{line[1 : len(line)-1], map[string]string{}})
		case len(k) > 0:
			key, value, ok := strings.Cut(line, "=")
			key = strings.TrimSpace(key)
			if ok && !strings.Contains(key, "[") {
				k[len(k)-1].keys[key] = unescape(strings.TrimSpace(value))
			}
		}
	}
	return k
}

func (k keyfile) get(name, key string) string {
	for _, g := range k {
		if g.name == name {
			return g.keys[key]
		}
	}
	return ""
}

func (g group) bool(key string) bool { return g.keys[key] == "true" }

// GLib's escapes: \s \n \t \r \\
func unescape(s string) string {
	if !strings.Contains(s, `\`) {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] != '\\' || i == len(s)-1 {
			b.WriteByte(s[i])
			continue
		}
		i++
		switch s[i] {
		case 's':
			b.WriteByte(' ')
		case 'n':
			b.WriteByte('\n')
		case 't':
			b.WriteByte('\t')
		case 'r':
			b.WriteByte('\r')
		default:
			b.WriteByte(s[i])
		}
	}
	return b.String()
}
