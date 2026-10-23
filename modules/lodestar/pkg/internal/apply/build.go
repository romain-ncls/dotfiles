package apply

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/romain-ncls/dotfiles/lodestar/internal/plan"
	"github.com/romain-ncls/dotfiles/lodestar/internal/state"
)

// asUser runs a command as the configured user. When lodestar itself runs
// as root (install, a container), it goes through runuser, with a temporary
// passwordless sudo rule for commands that call sudo (makepkg -i, yay).
func (e *env) asUser(needsSudo bool, args ...string) error {
	if os.Geteuid() != 0 {
		return e.run(args...)
	}
	if needsSudo {
		rule := e.root + "/etc/sudoers.d/00-lodestar-build"
		// SYSTEMD_IN_CHROOT (set by arch-chroot) tells pacman's hooks that
		// nothing runs here; sudo would drop it.
		content := "Defaults env_keep += \"SYSTEMD_IN_CHROOT\"\n" + e.user + " ALL=(ALL:ALL) NOPASSWD: ALL\n"
		if err := os.WriteFile(rule, []byte(content), 0o440); err != nil {
			return err
		}
		defer os.Remove(rule) // whatever happens to the command
	}
	return e.run(append([]string{"runuser", "-u", e.user, "--", "env", "HOME=" + e.home}, args...)...)
}

// cache is lodestar's folder in the user's ~/.cache.
func (e *env) cache(parts ...string) string {
	return filepath.Join(append([]string{e.root + e.home, ".cache", "lodestar"}, parts...)...)
}

// build fetches (for a git source), builds and installs a local package.
func (e *env) build(a *plan.Action) error {
	dir := a.Dir
	if a.Git != "" {
		src := e.cache("src", a.Module)
		if _, err := os.Stat(filepath.Join(src, ".git")); err != nil {
			if err := e.asUser(false, "git", "clone", "--no-checkout", a.Git, src); err != nil {
				return err
			}
		}
		if err := e.asUser(false, "git", "-C", src, "fetch", "--depth", "1", "origin", a.Commit); err != nil {
			return err
		}
		if err := e.asUser(false, "git", "-C", src, "checkout", "--force", "--detach", a.Commit); err != nil {
			return err
		}
		dir = filepath.Join(src, a.PkgPath)
	}
	moduleDir := filepath.Dir(dir)
	env := []string{"env",
		"BUILDDIR=" + e.cache("build"), "PKGDEST=" + e.cache("pkgs"), "SRCDEST=" + e.cache("sources"),
		"LODESTAR_MODULE_DIR=" + moduleDir, "LODESTAR_REPO=" + e.repo,
	}
	for _, d := range []string{e.cache("build"), e.cache("pkgs"), e.cache("sources")} {
		if err := e.mkdirs(d); err != nil {
			return err
		}
		if e.owner != nil {
			os.Chown(d, e.owner.uid, e.owner.gid)
		}
	}
	makepkg := append(append([]string{}, env...), "sh", "-c", `cd "$0" && exec makepkg --syncdeps --force --install --rmdeps --noconfirm`, dir)
	if err := e.asUser(true, makepkg...); err != nil {
		return err
	}
	names, err := e.pkgnames(dir)
	if err != nil {
		return err
	}
	e.st.Packages[a.Module] = state.Built{Hash: a.Hash, Names: names}
	return nil
}

// pkgnames reads the package names a PKGBUILD builds.
func (e *env) pkgnames(dir string) ([]string, error) {
	cmd := exec.Command("makepkg", "--printsrcinfo")
	cmd.Dir = dir
	if os.Geteuid() == 0 {
		cmd = exec.Command("runuser", "-u", e.user, "--", "sh", "-c", `cd "$0" && makepkg --printsrcinfo`, dir)
	}
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("makepkg --printsrcinfo: %w", err)
	}
	var names []string
	for _, line := range strings.Split(string(out), "\n") {
		if v, ok := strings.CutPrefix(strings.TrimSpace(line), "pkgname = "); ok {
			names = append(names, v)
		}
	}
	return names, nil
}

// hook runs a hook in its folder: a script there, or a command.
func (e *env) hook(a *plan.Action) error {
	script := filepath.Join(a.Dir, a.Command)
	args := []string{"sh", "-c", a.Command}
	if fi, err := os.Stat(script); err == nil && fi.Mode().IsRegular() {
		args = []string{"sh", script}
		if fi.Mode()&0o111 != 0 {
			args = []string{script}
		}
	}
	env := []string{"env", "LODESTAR_MODULE_DIR=" + a.Dir, "LODESTAR_REPO=" + e.repo}
	full := append([]string{"sh", "-c", `cd "$0" && exec "$@"`, a.Dir}, append(env, args...)...)
	var err error
	if a.Phase == plan.PhaseHome {
		err = e.asUser(false, full...)
	} else {
		err = e.run(full...)
	}
	if err != nil {
		return err
	}
	if !a.Always {
		e.st.Hooks[a.HookKey] = a.Hash
	}
	return nil
}

// writeJSON replaces a JSON file, keeping its mode.
func (e *env) writeJSON(a *plan.Action) error {
	a.Mode = 0o644
	if fi, err := os.Stat(e.root + a.Path); err == nil {
		a.Mode = fi.Mode().Perm()
	}
	return e.write(a)
}

// bootstrapYay builds yay from the AUR when it isn't installed yet (a fresh
// install): yay installs the other AUR packages.
func (e *env) bootstrapYay() error {
	if _, err := exec.LookPath("yay"); err == nil {
		return nil
	}
	fmt.Fprintln(e.out, "    yay is not installed yet: building it from the AUR first")
	src := e.cache("src", "yay")
	os.RemoveAll(src)
	if err := e.mkdirs(filepath.Dir(src)); err != nil {
		return err
	}
	if e.owner != nil {
		os.Chown(filepath.Dir(src), e.owner.uid, e.owner.gid)
	}
	if err := e.asUser(false, "git", "clone", "--depth", "1", "https://aur.archlinux.org/yay.git", src); err != nil {
		return err
	}
	return e.asUser(true, "sh", "-c", `cd "$0" && exec makepkg --syncdeps --install --rmdeps --noconfirm`, src)
}
