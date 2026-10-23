# dotfiles

Complete configuration for my Arch Linux machines: the home PC (`menadion`,
dual-boot with Windows) and the work laptop (`wandersail`, LUKS). Everything
that can be scripted is here; everything else is in
[docs/manual-steps.md](docs/manual-steps.md).

**lodestar** (`modules/lodestar/`, typed `lds`) makes a machine match this repo:
packages, `/etc`, services, firewall, boot, `$HOME`, KDE settings, and the
install from the live USB. Its design: [docs/tool-design.md](docs/tool-design.md).

## Day to day

```sh
lds plan       # what apply would change
lds apply      # make the machine match the repo (asks for the password once)
lds drift      # what is on the machine but not in the repo
lds upgrade    # yay -Syu, then rebuild our own packages if needed
lds kde review # keep, ignore or undo what changed in System Settings
```

Change the repo first, then apply. `lds drift` should be clean before each commit.

## New machine

From the Arch live USB:

```sh
loadkeys fr
iwctl station wlan0 connect "<SSID>"     # or ethernet
curl -fsSL https://raw.githubusercontent.com/romain-ncls/dotfiles/main/install.sh | bash -s -- <host>
```

Then the manual steps in [docs/manual-steps.md](docs/manual-steps.md)
(BIOS, SSH key, Bitwarden login, …).

## Layout

```
hosts/<host>/     host.yaml (modules, user, install settings) and host-only files
modules/<module>/ module.yaml, and system/ (files for /), home/ (files for $HOME), pkg/ (a local package)
                  modules/lodestar/pkg/ is lodestar's own Go source
schema/           JSON Schemas for completion in VS Code (lodestar schema)
docs/             design, decisions, manual steps
```
