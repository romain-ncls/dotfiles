package ui

import "testing"

func TestDiff(t *testing.T) {
	for _, tc := range []struct{ old, new, want string }{
		{"a\nb\nc\n", "a\nB\nc\n", "@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n"},
		{"", "x\n", "@@ -0,0 +1,1 @@\n+x\n"},
		{"x\n", "", "@@ -1,1 +0,0 @@\n-x\n"},
		{"1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n", "1\n2\n3\n4\n5\n6\n7\n8\n9\nX\n",
			"@@ -7,4 +7,4 @@\n 7\n 8\n 9\n-10\n+X\n"},
		// two changes far apart make two hunks
		{"a\n1\n2\n3\n4\n5\n6\n7\n8\nb\n", "A\n1\n2\n3\n4\n5\n6\n7\n8\nB\n",
			"@@ -1,4 +1,4 @@\n-a\n+A\n 1\n 2\n 3\n@@ -7,4 +7,4 @@\n 6\n 7\n 8\n-b\n+B\n"},
	} {
		if got := Diff([]byte(tc.old), []byte(tc.new)); got != tc.want {
			t.Errorf("Diff(%q, %q) =\n%s\nwant\n%s", tc.old, tc.new, got, tc.want)
		}
	}
	if got := Diff([]byte("a\x00"), []byte("b")); got != "binary content differs" {
		t.Errorf("binary: %q", got)
	}
}
