# dotfiles

Complete configuration for my two Arch Linux machines: the home PC (MENADION,
dual-boot with Windows) and the work PC (LUKS, single boot). Everything that
can be scripted is here; everything else is in [docs/manual-steps.md](docs/manual-steps.md).

- `$HOME` is managed by [chezmoi](https://chezmoi.io) from `home/`.
- The system (packages, `/etc`, `/boot`, services) is managed by
  [aconfmgr](https://github.com/CyberShadow/aconfmgr) from `system/`.
- [`just`](https://just.systems) wraps both.

## Day to day

```sh
just diff      # what apply would change
just apply     # make the machine match the repo (system, then home)
just drift     # list anything on the machine the repo does not know about
```

Change the repo first, then apply. `just drift` should be clean before each commit.

## New machine

1. Install Arch from the live USB with `install/` (see [install/README.md](install/README.md)).
2. Boot it, log in, then:
   ```sh
   sudo pacman -S --needed git chezmoi just bitwarden-cli
   yay -S aconfmgr-git        # after installing yay, see install/README.md
   git clone https://github.com/<you>/dotfiles ~/dotfiles
   chezmoi init --source ~/dotfiles   # asks "home" or "work" unless the hostname is menadion
   just apply
   ```
3. Do the manual steps in [docs/manual-steps.md](docs/manual-steps.md)
   (BIOS, SSH key, Bitwarden login, …).

## Layout

```
home/       chezmoi source for $HOME (.chezmoiroot points here)
  .kde/     KDE settings as one key per line, per role
system/     aconfmgr configuration (packages, /etc, /boot, services)
install/    live-USB install scripts, per role
scripts/    helpers used by chezmoi and just
windows/    Windows-side files for the home PC
docs/       manual steps and design decisions
```
