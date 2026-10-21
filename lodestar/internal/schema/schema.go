// Package schema generates the JSON Schemas VS Code uses to complete and check
// host.yaml and module.yaml.
package schema

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"

	"github.com/invopop/jsonschema"

	"github.com/romain-ncls/dotfiles/lodestar/internal/config"
)

const goPackage = "github.com/romain-ncls/dotfiles/lodestar"

// Write generates schema/host.json and schema/module.json in repo. The field
// descriptions come from the Go comments in repo/lodestar.
func Write(repo string) ([]string, error) {
	r := &jsonschema.Reflector{
		FieldNameTag:   "yaml",
		DoNotReference: true,
		ExpandedStruct: true,
		Mapper:         mapper,
	}
	// AddGoComments derives import paths from paths relative to the current
	// directory, so read the comments from inside the source tree.
	src := filepath.Join(repo, "lodestar")
	cwd, err := os.Getwd()
	if err != nil {
		return nil, err
	}
	if err := os.Chdir(src); err != nil {
		return nil, err
	}
	err = r.AddGoComments(goPackage, ".")
	os.Chdir(cwd)
	if err != nil {
		return nil, fmt.Errorf("reading the Go comments in %s: %w", src, err)
	}

	dir := filepath.Join(repo, "schema")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	var written []string
	kde, keys := kdeSchema()
	for name, v := range map[string]any{"host": &config.Host{}, "module": &config.Module{}} {
		s := r.Reflect(v)
		desc := ""
		if old, ok := s.Properties.Get("kde"); ok {
			desc = old.Description
		}
		k := *kde
		k.Description = desc
		s.Properties.Set("kde", &k)
		s.ID = jsonschema.ID("https://github.com/romain-ncls/dotfiles/schema/" + name + ".json")
		s.Title = map[string]string{"host": "lodestar host", "module": "lodestar module"}[name]
		data, err := json.MarshalIndent(s, "", "  ")
		if err != nil {
			return nil, err
		}
		p := filepath.Join(dir, name+".json")
		if err := os.WriteFile(p, append(data, '\n'), 0o644); err != nil {
			return nil, err
		}
		written = append(written, p)
	}
	if keys > 0 {
		written = append(written, fmt.Sprintf("(%d KDE keys described from .kcfg files)", keys))
	}
	return written, nil
}

// mapper describes the types that read their YAML in their own way.
func mapper(t reflect.Type) *jsonschema.Schema {
	switch t {
	case reflect.TypeFor[config.Value]():
		return anyValue()
	case reflect.TypeFor[config.StringList]():
		return &jsonschema.Schema{AnyOf: []*jsonschema.Schema{{Type: "string"}, {Type: "array", Items: &jsonschema.Schema{Type: "string"}}}}
	}
	if t == reflect.TypeFor[config.Mode]() {
		return &jsonschema.Schema{
			Description: "Mode in octal, like 0440. Quotes are optional.",
			AnyOf: []*jsonschema.Schema{
				{Type: "string", Pattern: "^0?[0-7]{3}$"},
				{Type: "integer"},
			},
		}
	}
	return nil
}
