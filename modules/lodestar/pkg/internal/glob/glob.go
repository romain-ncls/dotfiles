// Package glob matches paths against shell-style globs where, as in
// aconfmgr's IgnorePath, * also matches across slashes.
package glob

import (
	"regexp"
	"strings"
)

// Matcher is a compiled list of globs.
type Matcher []*regexp.Regexp

// New compiles the globs of every list.
func New(lists ...[]string) Matcher {
	var m Matcher
	for _, list := range lists {
		for _, g := range list {
			var sb strings.Builder
			sb.WriteString("^")
			for _, ch := range g {
				switch ch {
				case '*':
					sb.WriteString(".*")
				case '?':
					sb.WriteString(".")
				default:
					sb.WriteString(regexp.QuoteMeta(string(ch)))
				}
			}
			sb.WriteString("$")
			m = append(m, regexp.MustCompile(sb.String()))
		}
	}
	return m
}

// Match tells whether s matches one of the globs.
func (m Matcher) Match(s string) bool {
	for _, re := range m {
		if re.MatchString(s) {
			return true
		}
	}
	return false
}
