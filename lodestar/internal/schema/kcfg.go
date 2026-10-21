package schema

import (
	"encoding/xml"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/invopop/jsonschema"
	orderedmap "github.com/pb33f/ordered-map/v2"
)

// kcfg is the part of a KConfigXT file (.kcfg) the schema uses.
type kcfg struct {
	File struct {
		Name string `xml:"name,attr"`
	} `xml:"kcfgfile"`
	Groups []struct {
		Name    string `xml:"name,attr"`
		Entries []struct {
			Name      string `xml:"name,attr"`
			Key       string `xml:"key,attr"`
			Type      string `xml:"type,attr"`
			Label     string `xml:"label"`
			WhatsThis string `xml:"whatsthis"`
			Default   string `xml:"default"`
			Choices   []struct {
				Name  string `xml:"name,attr"`
				Value string `xml:"value,attr"`
			} `xml:"choices>choice"`
		} `xml:"entry"`
	} `xml:"group"`
}

// argFiles names the config file of .kcfg files that leave it to the
// program (<kcfgfile arg="true"/>).
var argFiles = map[string]string{
	"kwin.kcfg":               "kwinrc",
	"nightlightsettings.kcfg": "kwinrc",
	"okular.kcfg":             "okularpartrc",
	"okular_core.kcfg":        "okularpartrc",
}

// kcfgDirs are the folders KDE installs .kcfg files to.
func kcfgDirs() []string {
	dirs := []string{"/usr/share/config.kcfg"}
	for _, d := range strings.Split(os.Getenv("XDG_DATA_DIRS"), ":") {
		if d != "" {
			dirs = append(dirs, filepath.Join(d, "config.kcfg"))
		}
	}
	return dirs
}

// kdeSchema describes the kde: section: every file, group and key KDE
// describes in its .kcfg files, with their types, choices and defaults.
// Other files, groups and keys stay allowed.
func kdeSchema() (*jsonschema.Schema, int) {
	files := map[string]map[string]map[string]*jsonschema.Schema{}
	seen := map[string]bool{}
	for _, dir := range kcfgDirs() {
		paths, _ := filepath.Glob(filepath.Join(dir, "*.kcfg"))
		for _, p := range paths {
			real, err := filepath.EvalSymlinks(p)
			if err != nil || seen[real] {
				continue
			}
			seen[real] = true
			data, err := os.ReadFile(p)
			if err != nil {
				continue
			}
			var k kcfg
			if xml.Unmarshal(data, &k) != nil {
				continue
			}
			if k.File.Name == "" {
				k.File.Name = argFiles[filepath.Base(p)]
			}
			if k.File.Name == "" || strings.Contains(k.File.Name, "$(") {
				continue
			}
			file := filepath.Base(k.File.Name)
			for _, g := range k.Groups {
				if g.Name == "" || strings.Contains(g.Name, "$(") {
					continue
				}
				for _, e := range g.Entries {
					name := e.Key
					if name == "" {
						name = e.Name
					}
					if name == "" || strings.Contains(name, "$(") {
						continue
					}
					if files[file] == nil {
						files[file] = map[string]map[string]*jsonschema.Schema{}
					}
					if files[file][g.Name] == nil {
						files[file][g.Name] = map[string]*jsonschema.Schema{}
					}
					files[file][g.Name][name] = entrySchema(e.Type, e.Label, e.WhatsThis, e.Default, e.Choices)
				}
			}
		}
	}

	count := 0
	fileProps := orderedmap.New[string, *jsonschema.Schema]()
	for _, file := range sortedKeys(files) {
		groupProps := orderedmap.New[string, *jsonschema.Schema]()
		for _, group := range sortedKeys(files[file]) {
			keyProps := orderedmap.New[string, *jsonschema.Schema]()
			for _, k := range sortedKeys(files[file][group]) {
				keyProps.Set(k, files[file][group][k])
				count++
			}
			groupProps.Set(group, &jsonschema.Schema{Type: "object", Properties: keyProps, AdditionalProperties: anyValue()})
		}
		fileProps.Set(file, &jsonschema.Schema{Type: "object", Properties: groupProps, AdditionalProperties: anyGroup()})
	}
	return &jsonschema.Schema{
		Type:                 "object",
		Description:          "KDE settings: file, then group (nested groups separated by /), then key and value.",
		Properties:           fileProps,
		AdditionalProperties: &jsonschema.Schema{Type: "object", AdditionalProperties: anyGroup()},
	}, count
}

func entrySchema(typ, label, whatsThis, def string, choices []struct {
	Name  string `xml:"name,attr"`
	Value string `xml:"value,attr"`
}) *jsonschema.Schema {
	desc := strings.TrimSpace(label)
	if w := strings.Join(strings.Fields(whatsThis), " "); w != "" {
		if desc != "" {
			desc += "\n\n"
		}
		desc += w
	}
	if d := strings.TrimSpace(def); d != "" && !strings.Contains(d, "(") {
		desc += "\n\nDefault: " + d
	}
	s := &jsonschema.Schema{Description: desc}
	switch strings.ToLower(typ) {
	case "bool":
		s.Enum = []any{true, false, "true", "false"}
	case "int", "uint", "int64", "uint64", "double":
		s.AnyOf = []*jsonschema.Schema{{Type: "number"}, {Type: "string"}}
	case "enum":
		for _, c := range choices {
			v := c.Value
			if v == "" {
				v = c.Name
			}
			s.Enum = append(s.Enum, v)
		}
		if len(s.Enum) == 0 {
			s.AnyOf = anyValue().AnyOf
		}
	default:
		s.AnyOf = anyValue().AnyOf
	}
	return s
}

// anyValue is any scalar: lodestar keeps it as written.
func anyValue() *jsonschema.Schema {
	return &jsonschema.Schema{AnyOf: []*jsonschema.Schema{{Type: "string"}, {Type: "number"}, {Type: "boolean"}, {Type: "null"}}}
}

func anyGroup() *jsonschema.Schema {
	return &jsonschema.Schema{Type: "object", AdditionalProperties: anyValue()}
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
