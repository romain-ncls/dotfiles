package plan

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/romain-ncls/dotfiles/lodestar/internal/state"
)

// vault counts the secrets read, which is when lodestar would ask for the
// master password.
type vault struct {
	reads    int
	unlocked bool
}

func (v *vault) Secret(item, field string) (string, error) {
	v.reads++
	return "s3cret-" + field, nil
}

func (v *vault) Unlocked() bool { return v.unlocked }

// A template with a Bitwarden secret is rendered for real (the vault
// unlocked) only when something it uses changed, or the file did.
func TestPlanSecretTemplate(t *testing.T) {
	const target = "/etc/private/conn"
	repo := map[string]string{
		"hosts/box/host.yaml": host,
		"modules/base/module.yaml": `
files:
  /etc/private/conn:
    mode: 0600
`,
		"modules/base/system/etc/private/conn.tmpl": "email={{ .vars.email }}\nkey={{ bitwarden \"Home\" \"password\" }}\n",
	}

	// fileLine returns the file's line of the plan ("" for none) and its action.
	fileLine := func(p *Plan) (string, *Action) {
		for i, s := range summary(p) {
			if strings.Contains(s, target) {
				return s, p.Actions[i]
			}
		}
		return "", nil
	}
	compute := func(t *testing.T, repo map[string]string, root string, v *vault, st *state.State) *Plan {
		t.Helper()
		c, _, m := setup(t, repo)
		p, err := Compute(Input{Config: c, Machine: m, Root: root, Secrets: v, System: st, HomeSt: state.New(), IDs: testIDs})
		if err != nil {
			t.Fatal(err)
		}
		return p
	}
	// applied returns a machine root and a state as after an apply of the
	// repo: the file written, its record kept.
	applied := func(t *testing.T) (string, *state.State) {
		t.Helper()
		root := t.TempDir()
		v := &vault{}
		p := compute(t, repo, root, v, state.New())
		line, a := fileLine(p)
		if line != "write "+target+" new" || v.reads == 0 {
			t.Fatalf("first apply: %q, %d reads", line, v.reads)
		}
		if a.Record.Skeleton == "" || !a.Secret {
			t.Fatalf("first apply: no skeleton recorded, or not secret: %+v", a.Record)
		}
		write(t, root, map[string]string{target: string(a.Content)})
		os.Chmod(filepath.Join(root, target), 0o600)
		st := state.New()
		st.Files[target] = a.Record
		return root, st
	}

	t.Run("unchanged", func(t *testing.T) {
		root, st := applied(t)
		v := &vault{}
		line, _ := fileLine(compute(t, repo, root, v, st))
		if line != "" || v.reads != 0 {
			t.Errorf("plan %q, %d reads; want nothing to do, no read", line, v.reads)
		}
	})

	t.Run("template changed", func(t *testing.T) {
		root, st := applied(t)
		changed := map[string]string{}
		for k, val := range repo {
			changed[k] = val
		}
		changed["modules/base/system/etc/private/conn.tmpl"] += "mtu=1360\n"
		v := &vault{}
		line, a := fileLine(compute(t, changed, root, v, st))
		if line != "write "+target+" content" || v.reads == 0 || !a.Secret {
			t.Errorf("plan %q, %d reads, secret %v; want a write after reading the vault", line, v.reads, a != nil && a.Secret)
		}
	})

	t.Run("file edited on the machine", func(t *testing.T) {
		root, st := applied(t)
		write(t, root, map[string]string{target: "key=typed by hand\n"})
		v := &vault{}
		line, _ := fileLine(compute(t, repo, root, v, st))
		if line != "write "+target+" content" || v.reads == 0 {
			t.Errorf("plan %q, %d reads; want a write after reading the vault", line, v.reads)
		}
	})

	t.Run("vault already open", func(t *testing.T) {
		root, st := applied(t)
		v := &vault{unlocked: true}
		line, _ := fileLine(compute(t, repo, root, v, st))
		if line != "" || v.reads == 0 {
			t.Errorf("plan %q, %d reads; want a real comparison, nothing to do", line, v.reads)
		}
	})

	t.Run("root-only folder", func(t *testing.T) {
		if os.Geteuid() == 0 {
			t.Skip("root reads every folder")
		}
		root, st := applied(t)
		dir := filepath.Join(root, "etc/private")
		os.Chmod(dir, 0)
		t.Cleanup(func() { os.Chmod(dir, 0o755) })
		v := &vault{}
		p := compute(t, repo, root, v, st)
		line, _ := fileLine(p)
		if line != "" || v.reads != 0 {
			t.Errorf("plan %q, %d reads; want nothing to do, no read", line, v.reads)
		}
		if p.Desired[target] != st.Files[target] {
			t.Errorf("desired %+v, want the recorded %+v", p.Desired[target], st.Files[target])
		}

		// Recorded before skeletons: read once, and record the skeleton.
		old := st.Files[target]
		old.Skeleton = ""
		st.Files[target] = old
		v = &vault{}
		line, _ = fileLine(compute(t, repo, root, v, st))
		if line != "adopt "+target+" already matches" || v.reads == 0 {
			t.Errorf("old state: plan %q, %d reads; want an adopt after reading the vault", line, v.reads)
		}
	})

}
