# Dotfiles: working rules for Claude

This repo declares two Arch Linux machines completely, and **lodestar** (our
own tool, `lodestar/`, typed `lds`) makes a machine match it. The rule:
**every config change on either machine is made here (or documented here) —
nothing lives only on the machine.** When a task changes the system or user
config, change the repo in the same task, have it applied, and say what you
changed. The tool's design and its reasons: `docs/tool-design.md`.

## Machines

| host | hardware | notes |
|---|---|---|
| `menadion` | MSI Z690, i9-12900K, RTX 3070 Ti, 4K TV | Dual-boot with Windows 11 on a shared ESP. btrfs + snapper + Limine. |
| `wandersail` | HP ProBook 460 G11, Core Ultra 5 125U, Arc iGPU | Work laptop. LUKS2 + btrfs + swapfile (hibernation), single boot. |

lodestar takes the host from the hostname (or `--host`).

## Where things go

Hosts and modules are folders with the same layout. Only `system/` and
`home/` are installed; a file's place there is its place on disk. Paths
written in a `host.yaml` or `module.yaml` are relative to its folder.

| what | where |
|---|---|
| which modules a host uses, its variables, user, install settings | `hosts/<host>/host.yaml` |
| packages, units, firewall ports, KDE keys, shortcuts, hooks… | `modules/<module>/module.yaml` (or the host file, which wins) |
| a file in `/` | `modules/<m>/system/…` (`system/etc/x` is `/etc/x`); mode, check, then: `files:` in the YAML |
| a file in `$HOME` | `modules/<m>/home/…` (`home/.config/x` is `~/.config/x`) |
| a template (Go text/template: `.vars`, `.user`, `fact`, `file`, `bitwarden`, `trim`) | the same file with a `.tmpl` suffix |
| something edited in place (mpv's config) | a folder of the module, `files: {~/.config/x: {link: folder}}` |
| KDE settings | `kde: file: group: key: value` — never whole rc files: KDE rewrites them. Files KDE only reads (themes, profiles) go in `home/`. |
| Breeze window exceptions, KWin window rules | `breeze-exceptions:`, `window-rules:` (lodestar owns the whole list) |
| global shortcuts | `shortcuts:` in the module that provides the command |
| keys of an app's JSON settings (Readest) | `json:` |
| a tool of ours (code + PKGBUILD) | `modules/<tool>/pkg/`; a tool with its own repo: `pkg: {git, ref, path}` |
| what isn't a file or a key | `hooks:` (a script of the module, `when: changed` or `always`) |
| the hand-written part of `/boot/limine.conf` | `boot.limine` in the host file |
| anything that cannot be scripted | `docs/manual-steps.md` |
| why something is the way it is | `docs/decisions.md` |

VS Code completes and checks the YAML files from `schema/` (regenerate it with
`lodestar schema` after changing lodestar's config types).

To find which KDE key a setting writes: `lodestar kde watch`. To see what was
changed in System Settings since the last apply: `lodestar kde review --list`.

## Workflow

- Change the repo, then apply. Do not edit the live machine first.
- `lodestar plan` shows what `lodestar apply` would change; `lodestar drift`
  lists what is on the machine but not in the repo. Both run without root:
  run them yourself, before and after a change.
- Exception, trials: the user may install a package ad hoc (`yay -S …`) just
  to try it. Don't push them through the repo for that. Once they decide,
  declare it (keep) or `lodestar prune` removes it (drop).
- `lodestar drift` should be clean before committing.
- Commit messages: `feat:`, `fix:`, `chore:`, `docs:` (with a scope when it
  helps: `feat(lodestar): …`). Commits are SSH-signed.
- Push right after every commit (no need to ask). Do not merge into `main`
  unless the user asks.

## Constraints when Claude does the work

- **Claude cannot run sudo.** Commands run without a TTY, so sudo cannot
  prompt, and each attempt counts as a failure towards the faillock lockout
  (3 → 10 min; `faillock --user romain --reset` clears it without sudo).
  `lodestar apply`, `prune` and `upgrade` ask for the password once: tell the
  user to run them in their terminal, piped to a log if you need the output
  (`lodestar apply 2>&1 | tee ~/apply.log`), then read the log and delete it.
- **The repo is public.** Never commit secrets, even encrypted. Secrets live in
  Bitwarden and templates read them at apply time
  (`{{ bitwarden "item" "password" }}`). SSH keys are per machine and never synced.
- Developing lodestar: `cd lodestar && go test ./...`; the container test
  (`lodestar/test/container.sh`, needs Docker) applies a small host to a
  throwaway Arch container and checks every resource.

## Home PC quirks (details in docs/decisions.md)

- NVIDIA modules must stay **out** of the initramfs `MODULES`, or resume from hibernation fails.
- `hid_logitech_dj hid_logitech_hidpp` **must** be in the initramfs, or the G305 misses its receiver.
- Rebuild the initramfs with `limine-mkinitcpio`, never `mkinitcpio -P`
  (lodestar does it after `mkinitcpio.conf` or `kernel/cmdline` change).
- Never hand-edit `/boot/limine.conf`: edit `hosts/menadion/limine.conf`;
  lodestar merges it and re-enrolls the config hash.
- Limine entry ids are `Arch-Linux.linux` and `Windows-11`; OS switching uses `bootctl set-oneshot`.
