// Package install turns a blank disk into a host, from the Arch live USB:
// partitions, LUKS2, btrfs and its swapfile, pacstrap, then lodestar apply
// inside the new system, snapper and Limine.
package install

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/romain-ncls/dotfiles/lodestar/internal/config"
	"github.com/romain-ncls/dotfiles/lodestar/internal/machine"
	"github.com/romain-ncls/dotfiles/lodestar/internal/render"
)

// Options are the install's inputs.
type Options struct {
	Repo string // the repo cloned on the live system
	Host string
	Disk string // a /dev path instead of install.disk (tests)
	Yes  bool   // don't ask to type the hostname (tests)
	Out  io.Writer
}

const (
	target     = "/mnt"
	btrfsOpts  = "noatime,compress=zstd:3,ssd,discard=async,space_cache=v2"
	luksMapper = "root"
)

// Subvolumes and where they are mounted; @snapshots is mounted after snapper
// made its config.
var subvolumes = []struct{ name, mount string }{
	{"@", "/"},
	{"@home", "/home"},
	{"@var_log", "/var/log"},
	{"@var_cache", "/var/cache"},
	{"@var_tmp", "/var/tmp"},
	{"@var_lib_docker", "/var/lib/docker"},
	{"@swap", "/swap"},
	{"@snapshots", ""},
}

type installer struct {
	Options
	c       *config.Config
	disk    string
	esp     string
	part    string // the second partition: LUKS, or btrfs
	rootDev string
	pass    string // LUKS passphrase
	pwd     string // user and root password
}

// Run installs the host.
func Run(o Options) error {
	c, err := config.Load(o.Repo, o.Host)
	if err != nil {
		return err
	}
	if c.Install == nil {
		return fmt.Errorf("hosts/%s/%s has no install: section", o.Host, config.HostFile)
	}
	in := &installer{Options: o, c: c}
	steps := []struct {
		title string
		run   func() error
	}{
		{"Checks", in.checks},
		{"Passwords", in.passwords},
		{"Disk", in.partition},
		{"Filesystems", in.filesystems},
		{"Facts", in.facts},
		{"Repo packages (pacstrap)", in.pacstrap},
		{"User and repo", in.userAndRepo},
		{"Snapper", in.snapper},
		{"The system (lodestar apply)", in.apply},
		{"Limine", in.limine},
		{"Passwords and remote", in.finishUser},
		{"Unmounting", in.unmount},
	}
	for _, s := range steps {
		in.say(s.title)
		if err := s.run(); err != nil {
			return fmt.Errorf("%s: %w", s.title, err)
		}
	}
	in.say("Installed. Remove the USB stick and reboot; then log in and run lodestar apply.")
	return nil
}

func (in *installer) say(s string) { fmt.Fprintf(in.Out, "\n\033[1;36m==> %s\033[0m\n", s) }

func (in *installer) run(args ...string) error {
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Stdout, cmd.Stderr = in.Out, in.Out
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%s: %w", strings.Join(args, " "), err)
	}
	return nil
}

func (in *installer) runInput(input string, args ...string) error {
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Stdin = strings.NewReader(input)
	cmd.Stdout, cmd.Stderr = in.Out, in.Out
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%s: %w", strings.Join(args, " "), err)
	}
	return nil
}

func output(args ...string) (string, error) {
	out, err := exec.Command(args[0], args[1:]...).Output()
	if err != nil {
		return "", fmt.Errorf("%s: %w", strings.Join(args, " "), err)
	}
	return strings.TrimSpace(string(out)), nil
}

func (in *installer) chroot(args ...string) error {
	return in.run(append([]string{"arch-chroot", target}, args...)...)
}

func (in *installer) checks() error {
	if os.Geteuid() != 0 {
		return errors.New("run as root on the Arch live USB")
	}
	if _, err := os.Stat("/run/archiso"); err != nil {
		return errors.New("this is not the Arch live USB: refusing to erase a disk of a running system")
	}
	if _, err := os.Stat("/sys/firmware/efi/efivars"); err != nil {
		return errors.New("not booted in UEFI mode")
	}
	if out, _ := output("findmnt", "-n", target); out != "" {
		return fmt.Errorf("%s is mounted: umount -R %s first", target, target)
	}
	if err := in.run("curl", "-fsS", "-o", "/dev/null", "--max-time", "15", "https://archlinux.org"); err != nil {
		return errors.New("no network: connect first (iwctl, or a cable)")
	}
	disk := in.Disk
	if disk == "" {
		disk = filepath.Join("/dev/disk/by-id", in.c.Install.Disk)
	}
	real, err := filepath.EvalSymlinks(disk)
	if err != nil {
		return fmt.Errorf("disk %s not found: is this the right machine?", disk)
	}
	if t, _ := output("lsblk", "-dno", "TYPE", real); t != "disk" {
		return fmt.Errorf("%s is a %q, not a whole disk", real, t)
	}
	in.disk = real
	model, _ := output("lsblk", "-dno", "MODEL,SIZE", real)
	in.run("lsblk", "-o", "NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS", real)
	fmt.Fprintf(in.Out, "\n\033[1;31mThis ERASES %s (%s) and installs %s on it.\033[0m\n", real, strings.Join(strings.Fields(model), " "), in.Host)
	if in.Yes {
		return nil
	}
	if answer := ask(fmt.Sprintf("Type the hostname (%s) to continue: ", in.Host)); answer != in.Host {
		return errors.New("aborted; nothing was changed")
	}
	return nil
}

// passwords asks everything at once, so the install then runs unattended.
// LODESTAR_TEST_PASSPHRASE and LODESTAR_TEST_PASSWORD answer for tests.
func (in *installer) passwords() error {
	var err error
	if in.c.Install.Encrypt {
		if in.pass = os.Getenv("LODESTAR_TEST_PASSPHRASE"); in.pass == "" {
			if in.pass, err = askTwice("Disk passphrase (LUKS, typed at every boot)"); err != nil {
				return err
			}
		}
	}
	if in.pwd = os.Getenv("LODESTAR_TEST_PASSWORD"); in.pwd == "" {
		if in.pwd, err = askTwice(fmt.Sprintf("Password for %s (and root)", in.c.User.Name)); err != nil {
			return err
		}
	}
	return nil
}

func (in *installer) partition() error {
	in.run("swapoff", "-a")
	if err := in.run("wipefs", "--all", in.disk); err != nil {
		return err
	}
	script := fmt.Sprintf("label: gpt\nsize=%s, type=uefi, name=ESP\ntype=linux, name=%s\n", in.c.Install.ESP, in.Host)
	if err := in.runInput(script, "sfdisk", "--wipe", "always", in.disk); err != nil {
		return err
	}
	in.run("udevadm", "settle")
	out, err := output("lsblk", "-lnpo", "NAME,TYPE", in.disk)
	if err != nil {
		return err
	}
	var parts []string
	for _, line := range strings.Split(out, "\n") {
		if f := strings.Fields(line); len(f) == 2 && f[1] == "part" {
			parts = append(parts, f[0])
		}
	}
	if len(parts) != 2 {
		return fmt.Errorf("expected 2 partitions on %s, found %v", in.disk, parts)
	}
	in.esp, in.part = parts[0], parts[1]
	if err := in.run("mkfs.fat", "-F", "32", "-n", "ESP", in.esp); err != nil {
		return err
	}
	in.rootDev = in.part
	if in.c.Install.Encrypt {
		if err := in.runInput(in.pass, "cryptsetup", "luksFormat", "--type", "luks2", "--batch-mode", "--key-file=-", in.part); err != nil {
			return err
		}
		if err := in.runInput(in.pass, "cryptsetup", "open", "--key-file=-", in.part, luksMapper); err != nil {
			return err
		}
		in.rootDev = "/dev/mapper/" + luksMapper
	}
	return nil
}

func (in *installer) filesystems() error {
	if err := in.run("mkfs.btrfs", "--force", "--label", "arch", in.rootDev); err != nil {
		return err
	}
	if err := in.run("mount", in.rootDev, target); err != nil {
		return err
	}
	for _, sv := range subvolumes {
		if err := in.run("btrfs", "subvolume", "create", filepath.Join(target, sv.name)); err != nil {
			return err
		}
	}
	if err := in.run("umount", target); err != nil {
		return err
	}
	for _, sv := range subvolumes {
		if sv.mount == "" {
			continue
		}
		dir := filepath.Join(target, sv.mount)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
		opts := btrfsOpts + ",subvol=" + sv.name
		if sv.name == "@swap" {
			opts = "noatime,ssd,subvol=@swap"
		}
		if err := in.run("mount", "-o", opts, in.rootDev, dir); err != nil {
			return err
		}
	}
	boot := filepath.Join(target, "boot")
	if err := os.MkdirAll(boot, 0o755); err != nil {
		return err
	}
	if err := in.run("mount", "-o", "fmask=0077,dmask=0077", in.esp, boot); err != nil {
		return err
	}
	if size := in.c.Install.Swapfile; size != "" {
		return in.run("btrfs", "filesystem", "mkswapfile", "--size", btrfsSize(size), "--uuid", "clear", filepath.Join(target, "swap/swapfile"))
	}
	return nil
}

// btrfsSize turns 32GiB into 32g.
func btrfsSize(s string) string {
	s = strings.TrimSpace(s)
	for _, u := range []string{"GiB", "MiB", "GB", "MB", "G", "M"} {
		if n, ok := strings.CutSuffix(s, u); ok {
			return n + strings.ToLower(u[:1])
		}
	}
	return s
}

// facts measures the new disk for the templates (fstab, kernel command
// line) and saves them where lodestar finds them later, as any user.
func (in *installer) facts() error {
	f := map[string]string{}
	var err error
	if f["root-uuid"], err = output("blkid", "-s", "UUID", "-o", "value", in.rootDev); err != nil {
		return err
	}
	if f["esp-uuid"], err = output("blkid", "-s", "UUID", "-o", "value", in.esp); err != nil {
		return err
	}
	if in.c.Install.Encrypt {
		if f["root-luks-uuid"], err = output("blkid", "-s", "UUID", "-o", "value", in.part); err != nil {
			return err
		}
	}
	if in.c.Install.Swapfile != "" {
		if f["resume-offset"], err = output("btrfs", "inspect-internal", "map-swapfile", "-r", filepath.Join(target, "swap/swapfile")); err != nil {
			return err
		}
	}
	path := target + render.CacheFile
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	data, _ := json.MarshalIndent(f, "", "  ")
	for k, v := range f {
		fmt.Fprintf(in.Out, "    %s: %s\n", k, v)
	}
	return os.WriteFile(path, append(data, '\n'), 0o644)
}

// pacstrap installs the host's repo packages, with the repo's pacman.conf
// (multilib) on the live system too.
func (in *installer) pacstrap() error {
	for _, f := range in.c.Files {
		if f.Target == "/etc/pacman.conf" && f.Source != "" {
			data, err := os.ReadFile(f.Source)
			if err != nil {
				return err
			}
			if err := os.WriteFile("/etc/pacman.conf", data, 0o644); err != nil {
				return err
			}
		}
	}
	if err := in.run("pacman", "-Sy", "--noconfirm", "--needed", "archlinux-keyring"); err != nil {
		return err
	}
	repos, err := machine.Local{}.InRepos()
	if err != nil {
		return err
	}
	var pkgs []string
	for _, p := range in.c.Packages {
		if repos[p.Name] {
			pkgs = append(pkgs, p.Name)
		}
	}
	fmt.Fprintf(in.Out, "    %d repo packages; AUR and local packages come with lodestar apply\n", len(pkgs))
	return in.run(append([]string{"pacstrap", "-K", target}, pkgs...)...)
}

// userAndRepo creates the user (lodestar apply sets the shell and groups)
// and copies the repo, with its history, to ~/dotfiles: paths written by
// apply (links into the repo) then point to where it stays.
func (in *installer) userAndRepo() error {
	user := in.c.User.Name
	if err := in.chroot("useradd", "--create-home", "--user-group", user); err != nil {
		return err
	}
	repo := filepath.Join(target, "home", user, "dotfiles")
	if err := in.run("cp", "-a", in.Repo, repo); err != nil {
		return err
	}
	if err := in.chroot("chown", "-R", user+":"+user, "/home/"+user+"/dotfiles"); err != nil {
		return err
	}
	self, err := os.Executable()
	if err != nil {
		return err
	}
	// Until lodestar's own package is built by the apply below.
	return in.run("install", "-Dm755", self, filepath.Join(target, "usr/local/bin/lodestar"))
}

// snapper makes the root config, then puts @snapshots where snapper's own
// .snapshots subvolume was. lodestar apply then writes the repo's config.
func (in *installer) snapper() error {
	if _, err := os.Stat(filepath.Join(target, "usr/bin/snapper")); err != nil {
		fmt.Fprintln(in.Out, "    snapper is not installed: skipped")
		return nil
	}
	if err := in.chroot("snapper", "--no-dbus", "-c", "root", "create-config", "/"); err != nil {
		return err
	}
	if err := in.run("btrfs", "subvolume", "delete", filepath.Join(target, ".snapshots")); err != nil {
		return err
	}
	snaps := filepath.Join(target, ".snapshots")
	if err := os.Mkdir(snaps, 0o750); err != nil {
		return err
	}
	return in.run("mount", "-o", btrfsOpts+",subvol=@snapshots", in.rootDev, snaps)
}

// apply runs lodestar apply in the new system, for the system part: the
// home part needs a Plasma session (first login). The machine id and a
// seeded limine.conf come first: the initramfs rebuild needs them.
func (in *installer) apply() error {
	if err := in.chroot("systemd-machine-id-setup"); err != nil {
		return err
	}
	id, err := os.ReadFile(filepath.Join(target, "etc/machine-id"))
	if err != nil {
		return err
	}
	seed := fmt.Sprintf("/Arch Linux\n    comment: machine-id=%s\n", strings.TrimSpace(string(id)))
	if err := os.WriteFile(filepath.Join(target, "boot/limine.conf"), []byte(seed), 0o600); err != nil {
		return err
	}
	return in.lodestarApply()
}

func (in *installer) lodestarApply() error {
	user := in.c.User.Name
	return in.chroot("/usr/local/bin/lodestar", "apply", "--system", "--yes",
		"--repo", "/home/"+user+"/dotfiles", "--host", in.Host)
}

// limine installs the boot loader to the ESP, builds the kernel entries,
// then applies again: lodestar merges the repo's part of limine.conf.
func (in *installer) limine() error {
	if _, err := os.Stat(filepath.Join(target, "usr/bin/limine-install")); err != nil {
		return errors.New("limine-install is missing: is limine-mkinitcpio-hook in the boot module?")
	}
	if err := in.chroot("limine-install"); err != nil {
		return err
	}
	if err := in.chroot("limine-mkinitcpio"); err != nil {
		return err
	}
	return in.lodestarApply()
}

func (in *installer) finishUser() error {
	user := in.c.User.Name
	if err := in.runInput(fmt.Sprintf("%s:%s\nroot:%s\n", user, in.pwd, in.pwd), "arch-chroot", target, "chpasswd"); err != nil {
		return err
	}
	if _, err := os.Stat(filepath.Join(target, "usr/bin/lodestar")); err == nil {
		os.Remove(filepath.Join(target, "usr/local/bin/lodestar"))
	}
	// Pushing goes over SSH, once the machine's key is on GitHub.
	repo := "/home/" + user + "/dotfiles"
	if url, err := output("git", "-C", target+repo, "remote", "get-url", "origin"); err == nil {
		if m := regexp.MustCompile(`^https://github\.com/(.+)$`).FindStringSubmatch(url); m != nil {
			in.run("git", "-C", target+repo, "remote", "set-url", "origin", "git@github.com:"+m[1])
		}
	}
	return nil
}

func (in *installer) unmount() error {
	in.run("sync")
	if err := in.run("umount", "-R", target); err != nil {
		return err
	}
	if in.c.Install.Encrypt {
		return in.run("cryptsetup", "close", luksMapper)
	}
	return nil
}

// ask reads a line from the terminal.
func ask(prompt string) string {
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		return ""
	}
	defer tty.Close()
	fmt.Fprint(tty, prompt)
	line, _ := bufio.NewReader(tty).ReadString('\n')
	return strings.TrimSpace(line)
}

// askTwice reads a secret twice, without echo, until both match.
func askTwice(what string) (string, error) {
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		return "", errors.New("no terminal to ask for " + what)
	}
	defer tty.Close()
	stty := func(arg string) {
		cmd := exec.Command("stty", arg)
		cmd.Stdin = tty
		cmd.Run()
	}
	stty("-echo")
	defer stty("echo")
	r := bufio.NewReader(tty)
	for {
		fmt.Fprintf(tty, "%s: ", what)
		a, _ := r.ReadString('\n')
		fmt.Fprintf(tty, "\nagain: ")
		b, _ := r.ReadString('\n')
		fmt.Fprintln(tty)
		a, b = strings.TrimRight(a, "\r\n"), strings.TrimRight(b, "\r\n")
		switch {
		case a == "":
			fmt.Fprintln(tty, "empty; try again")
		case a != b:
			fmt.Fprintln(tty, "they differ; try again")
		default:
			return a, nil
		}
	}
}
