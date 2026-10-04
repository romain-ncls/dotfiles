# Dotfiles: working rules for Claude

This repo declares two Arch Linux machines completely. The rule is: **every
config change on either machine is made here (or documented here) — nothing
lives only on the machine.** When a task changes the system or user config,
change the repo in the same task, apply it, and say what you changed.

## Machines

| role | hostname | notes |
|---|---|---|
| `home` | `menadion` | MSI Z690, i9-12900K, RTX 3070 Ti, 4K TV. Dual-boot with Windows 11 on a shared ESP. btrfs + snapper + Limine. |
| `work` | (not installed yet; start with `install/WORK.md`) | Intel Core Ultra 5 125U, integrated graphics only. LUKS, no dual-boot. |

The role comes from `.chezmoi.toml.tmpl` (`menadion` → `home`, anything else asks once).

## Where things go

| what | where | applied by |
|---|---|---|
| files in `$HOME` | `home/` (chezmoi source; `.chezmoiroot` points here) | `just apply-home` |
| per-role differences in `$HOME` | templates using `.role`, and `home/.chezmoiignore` | |
| KDE / Plasma settings | one line per key in `home/.kde/{common,home,work}.tsv` | `scripts/kde-config` via a chezmoi run script |
| Readest settings | the chosen keys in `home/.readest/{common,home,work}.json` | `scripts/readest-config` via a chezmoi run script |
| mpv config (shared with Windows) | `mpv/` at the repo root: `~/.config/mpv` is a symlink to it; on Windows `%APPDATA%\mpv` is a junction to a clone (`windows/Setup-Mpv.ps1`) | edit in place, commit, `git pull` on the other side; `just drift` flags uncommitted changes |
| mouse acceleration | `scripts/flat-mice` (flat for every mouse) | every `chezmoi apply` |
| hand-written part of `/boot/limine.conf` (globals, Windows entry) | `system/limine/<role>.conf` | `scripts/limine-conf` from `just apply-system` |
| packages, `/etc`, services | `system/` (aconfmgr: `10-*.sh` common, `50-home.sh`, `50-work.sh`, files under `system/files/`) | `just apply-system` |
| fresh install from the live USB | `install/lib.sh` (shared) + `install/<host>.sh`; work PC: `install/WORK.md` | by hand, `install/README.md` |
| Windows side of the home PC | `windows/` | by hand |
| anything that cannot be scripted | `docs/manual-steps.md` | by hand |
| why something is the way it is | `docs/decisions.md` | |

Per-role differences in `system/`: guard with `if [[ $HOSTNAME == menadion ]]`
or put them in `50-home.sh` / `50-work.sh`, which test the hostname themselves.

KDE (and Readest) rewrite their config files constantly, so never add whole KDE rc
files or Readest's `settings.json` to chezmoi. Add the single key to the right
`.tsv` / `.readest/*.json` instead. Find the key by
diffing `~/.config` before and after changing the setting in the GUI.

## Workflow

- Change the repo, then apply. Do not edit the live machine first.
- `just drift` must come back clean before committing. It runs `aconfmgr save`
  (anything unrecorded lands in `system/99-unsorted.sh`: sort it into the right
  file or delete it), `chezmoi status`, and the KDE key check.
- If something was changed on the machine directly, bring it into the repo:
  `chezmoi add <file>` for `$HOME`, the `.tsv` files for KDE, `system/` for the rest.
- Commit messages follow the old repo's style: `feat:`, `fix:`, `chore:`, `docs:`.
  Commits are SSH-signed (see `.gitconfig`).
- Push right after every commit (no need to ask). Do not merge into `main`
  unless the user asks.

## Constraints when Claude does the work

- **Claude cannot run sudo.** Commands run without a TTY, so sudo cannot prompt,
  and each attempt counts as a failure towards the faillock lockout (3 → 10 min;
  `faillock --user romain --reset` clears it without sudo). For anything needing
  root — `just apply-system`, `just drift`, pacman — write the command or a
  script for the user to run in their own terminal, piped to a log:
  `… 2>&1 | tee ~/some.log`. Then read the log, and delete it afterwards.
- `chezmoi apply`, `scripts/kde-config`, `kwriteconfig6`, `busctl --user` all
  run fine without root.
- **The repo is public.** Never commit secrets, even encrypted. Secrets live in
  Bitwarden and are pulled at apply time by templates (`{{ (bitwarden "item" "name").login.password }}`
  or `bitwardenFields`); chezmoi runs `bw unlock` itself (`bitwarden.unlock = "auto"`).
  SSH keys are per machine and never synced.

## Home PC quirks (details in docs/decisions.md)

- NVIDIA modules must stay **out** of the initramfs `MODULES`, or resume from hibernation fails.
- `hid_logitech_dj hid_logitech_hidpp` **must** be in the initramfs, or the G305 misses its receiver.
- Rebuild the initramfs with `limine-mkinitcpio`, never `mkinitcpio -P`.
- Never hand-edit `/boot/limine.conf`: edit `system/limine/home.conf` and `just apply-system`
  (merges, then `limine-update` re-enrolls the config hash).
- Limine entry ids are `Arch-Linux.linux` and `Windows-11`; OS switching uses `bootctl set-oneshot`.
