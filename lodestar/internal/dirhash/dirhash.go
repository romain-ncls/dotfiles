// Package dirhash hashes folders: their file names, modes and contents.
package dirhash

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
)

// skip are folders a hash never looks into: version control and build
// output.
var skip = map[string]bool{".git": true, "target": true, "node_modules": true}

// Sum hashes the folders (or files) in order, plus extra strings.
func Sum(paths []string, extra ...string) (string, error) {
	h := sha256.New()
	for _, e := range extra {
		fmt.Fprintf(h, "extra %q\n", e)
	}
	for _, root := range paths {
		err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if d.IsDir() && p != root && skip[d.Name()] {
				return filepath.SkipDir
			}
			info, err := os.Lstat(p)
			if err != nil {
				return err
			}
			rel, _ := filepath.Rel(root, p)
			fmt.Fprintf(h, "%s %o\n", rel, info.Mode()&(fs.ModeType|0o111))
			switch {
			case info.Mode()&fs.ModeSymlink != 0:
				target, err := os.Readlink(p)
				if err != nil {
					return err
				}
				fmt.Fprintf(h, "-> %s\n", target)
			case info.Mode().IsRegular():
				f, err := os.Open(p)
				if err != nil {
					return err
				}
				_, err = io.Copy(h, f)
				f.Close()
				if err != nil {
					return err
				}
			}
			return nil
		})
		if err != nil {
			return "", err
		}
	}
	return hex.EncodeToString(h.Sum(nil))[:16], nil
}
