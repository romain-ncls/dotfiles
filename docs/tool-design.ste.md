# Config tool: design (STE version)

> This file gives the same design as [tool-design.md](tool-design.md). It uses
> the rules of ASD-STE100 Simplified Technical English. The words are not
> compared with the official STE dictionary.
>
> Status: agreed on 21 October 2026. The configuration tool is **lodestar**.
> Its fish abbreviation is `lds`. The hostname of the work laptop is
> **wandersail**. Section 13 gives the decisions.

## Technical names and verbs

This document uses these technical names. Each name has one definition only.

| Name | Definition |
|---|---|
| lodestar | The configuration tool. It is one Go program. |
| repository | The git repository `~/dotfiles`. It contains the configuration of all the machines. |
| host | One machine. Each host has one folder, `hosts/<hostname>/`, with one host file, `host.yaml`. |
| module | One folder in `modules/`, with one module file, `module.yaml`. It contains one part of the configuration, for example Docker. |
| resource | One item that a module declares, for example a package, a file or a firewall port. |
| Arch package | A package from the pacman sync databases (core, extra, multilib). |
| AUR package | A package from the Arch User Repository. |
| local package | A package that makepkg builds from a PKGBUILD. The PKGBUILD is in a module or in the git repository of a tool. |
| ref | A git tag, a git commit or a git branch. |
| system file | A file outside `$HOME`, for example a file in `/etc`. |
| home file | A file in `$HOME`. |
| unit | A systemd unit. |
| plan | The list of changes that `lodestar apply` will make. |
| drift | An item on the machine that the repository does not declare. |
| state file | A file where lodestar records the changes that it made. |
| KDE snapshot | A copy of the KDE files that lodestar makes after each apply operation. |
| fact | A value that lodestar reads from the machine, for example a disk UUID. |
| secret | A password or a private key. Secrets are in Bitwarden only. |

This document uses these technical verbs for computer processes: declare,
install, build, download, fetch, clone, enable, disable, boot, prompt, merge,
encrypt.

## 1. Why lodestar replaces the current tools

The current configuration has four problems:

- **It uses two tools with different models.** aconfmgr uses a bash language
  for the system. chezmoi uses special file names for `$HOME`, for example
  `private_dot_config`. `just` and seven scripts connect the two tools.
- **Custom scripts already do the difficult tasks.** Scripts set the KDE keys
  and the Readest keys. Scripts also build the local packages, merge
  `limine.conf` and set the mouse acceleration. aconfmgr and chezmoi cannot do
  these tasks.
- **The installation and the apply operation use different code.**
  `scripts/aconf-packages` and `install/lib.sh` copy the aconfmgr language with
  empty functions. This is because aconfmgr cannot read the configuration of a
  different host. It also cannot apply a configuration to `/mnt`.
- **All operations must run as root.** aconfmgr reads the file system as root,
  also for a diff. Because of this, `just diff` and `just drift` always show a
  password prompt. Claude cannot do a drift check.

## 2. Goals

lodestar must do these tasks:

- Describe each machine in data files. A person must be able to read these
  files without knowledge of lodestar.
- Show all changes before it makes them. `lodestar plan` shows the changes that
  `lodestar apply` will make. `lodestar plan` does not use root.
- Show one password prompt only during `lodestar apply`.
- Find drift. `lodestar drift` shows all the items on the machine that the
  repository does not declare.
- Remove packages that the repository does not declare, with `lodestar prune`.
- Install a host from the live USB. `lodestar install <host>` changes a blank
  disk into that host. The person types only passwords.
- Operate from all folders. lodestar is a package with fish completions.

lodestar does not do these tasks:

- **It does not copy Nix.** It has no generations, no store and no expression
  language. snapper does the rollback. lodestar makes a snapper snapshot
  before and after each apply operation.
- **It operates on one machine with Arch Linux.** It does not operate on other
  distributions, for other users or on remote machines.
- **It does not build packages itself.** pacman installs Arch packages. yay
  builds AUR packages. makepkg builds local packages.

## 3. Hosts and modules

### 3.1 Layout of the repository

```
hosts/
  menadion/
    host.yaml         modules, variables, install settings, host-only settings
    system/  home/    host-only files
    windows/          the Windows side of the dual boot (not installed)
  wandersail/
    host.yaml
modules/
  mutectl/
    module.yaml       what the module declares
    system/           files for /       (system/etc/… is /etc/…)
    home/             files for $HOME   (home/.config/… is ~/.config/…)
    pkg/              a local package: its PKGBUILD and sources
  mpv/
    module.yaml
    config/           mpv's config: linked to ~/.config/mpv, used by Windows too
    windows/          Setup-Mpv.ps1
  lodestar/
    module.yaml
    pkg/              lodestar's Go source and PKGBUILD
    test/             the container and VM tests
  base/  desktop/  kde/  laptop/  dev/  docker/  …
schema/               JSON Schemas generated by lodestar, for completion in VS Code
.vscode/              settings.json: the schemas, and editor tab names
docs/
install.sh            run from the live USB: builds lodestar, starts the install (§9)
```

- **Hosts and modules have the same layout.** Each host and each module is a
  folder. The name of the folder is the hostname or the module name. A host is
  a module with more settings: `modules`, `vars`, `user` and `install`.
- **lodestar installs only `system/` and `home/`.** The path of a file under
  these folders is its path on the machine. For example,
  `modules/base/system/etc/locale.conf` goes to `/etc/locale.conf`. The file
  `modules/git/home/.gitconfig` goes to `~/.gitconfig`. lodestar does not use
  special file names. A file name that ends with `.tmpl` is a template (refer
  to Section 5).
- **`pkg/` contains the local package of the module.** When a host includes the
  module, lodestar installs this package. Thus all the parts of a tool are in
  one folder: the code, the PKGBUILD, the unit, the shortcuts and the ports. If
  a tool has its own git repository, `module.yaml` points to that repository
  (refer to Section 4.1).
- **lodestar does not install the other folders.** Links and hooks use them,
  for example the `config/` folder of mpv. A path in a `host.yaml` or
  `module.yaml` file is relative to the folder of that file.
- **lodestar is a module, as the other tools are.** The folder
  `modules/lodestar/pkg/` contains the source of lodestar and its PKGBUILD. The
  folder `modules/lodestar/test/` contains its tests.

### 3.2 Host file

lodestar writes `/etc/hostname` from the name of the host folder.

```yaml
# hosts/wandersail/host.yaml
modules:
  - base
  - desktop
  - kde
  - laptop
  - dev
  - docker
  - mutectl
  - spotify-vol
  - work

vars:                      # available to templates
  email: nicolasromain0@gmail.com

user:
  name: romain
  shell: /usr/bin/fish
  groups:
    - wheel
    - docker
    - input

install:                   # read only by `lodestar install` (Section 9)
  disk: nvme-SK_hynix_BC901_HFS512GEJ9X108N_<serial>   # /dev/disk/by-id name; lodestar refuses all other disks
  esp: 4GiB
  encrypt: true
  swapfile: 32GiB

# A host file can declare all the resources that a module can declare.
# A value in the host file replaces the values from the modules.
kde:
  kscreenlockerrc:
    Daemon:
      Timeout: 6
```

### 3.3 Module file

```yaml
# modules/kdeconnect/module.yaml
packages:
  - kdeconnect
  - sshfs                  # browse the files of the phone

firewall:
  tcp:
    - 1714-1764
  udp:
    - 1714-1764
```

```yaml
# modules/mutectl/module.yaml   (pkg/ contains the PKGBUILD and the Go source)
services:
  - mutectl.service

shortcuts:
  - name: Mute
    keys: Meta+É
    run: mutectl mute
```

### 3.4 Merge rules

lodestar merges the modules of a host with these rules:

- **Lists are sets.** lodestar adds together the packages, units, firewall
  ports and groups from all the modules.
- **A single value comes from the last module that sets it.** The sequence is
  the sequence of the modules in the host file. A value in the host file
  replaces the values from all the modules. `lodestar plan --explain <key>`
  shows the source of a value.
- **Two modules cannot supply the same file.** If two modules supply the same
  file, lodestar stops with an error. To replace the file of a module on one
  host, use the host folder. Put a file with the same path in its `system/` or
  `home/` folder.

### 3.5 Edit in VS Code

- **Schema.** `lodestar schema` makes JSON Schemas from the Go types of
  lodestar. It writes them into `schema/`. Thus the schemas and the code always
  agree. `.vscode/settings.json` connects `hosts/*/host.yaml` and
  `modules/*/module.yaml` to these schemas for the Red Hat YAML extension. The
  files do not need a header comment.
- **Editor functions.** The editor completes keys and their possible values.
  It shows the description of a key when the pointer is on the key. It shows
  an error immediately for an unknown key or an incorrect type.
- **Tab names.** All module files have the name `module.yaml`. Thus
  `.vscode/settings.json` gives each editor tab the name of its folder
  (`workbench.editor.customLabels.patterns`), for example `mutectl (module)`
  or `wandersail (host)`.
- **KDE keys.** KDE describes many of its settings in `.kcfg` files, with types
  and possible values. The laptop has 85 of these files. `kwin.kcfg` alone
  describes 93 settings. lodestar adds these settings to the schema (step 2 of
  Section 11). The settings that KDE does not describe have no completion, for
  example shortcuts and the panel layout.
- **YAML problems.** lodestar reads each field into a declared type. An
  unknown key causes an error with the file and the line. lodestar keeps KDE
  values as you write them. Thus `no` stays `no`, and `0440` stays `0440`.

## 4. Resources

| Resource | Declared in | If you remove the declaration | Drift shows |
|---|---|---|---|
| Packages | `packages:`, or `pkg/` or `pkg:` in a module | The package stays until `lodestar prune`. | Explicit packages that are not declared. Declared packages that are not installed. |
| System files | `system/` | lodestar restores the package version, or removes the file. | Package files that changed. Files in `/etc` that no package owns. |
| Home files | `home/` | lodestar removes the file if nobody changed it. | Home files that changed on the machine. |
| Units | `services:`, `user-services:` | lodestar disables the unit. | Units that somebody enabled with `systemctl`. A package preset is not drift. |
| User and groups | `user:` | No change. | Groups of the user that are not declared. |
| Firewall ports | `firewall:` | lodestar closes the port. | Nothing. lodestar writes all of the ruleset. |
| KDE keys | `kde: <file>: <group>:` | lodestar removes the key. KDE then uses its default value. | Keys with a different value on the machine. Keys that changed in System Settings after the last apply operation. |
| KDE lists | `breeze-exceptions:`, `window-rules:` | lodestar removes the entry and gives new numbers to the other entries. | Entries that somebody added in System Settings. |
| Shortcuts | `shortcuts:` | lodestar removes the shortcut. | Nothing. |
| JSON keys | `json:` | No change, because lodestar does not know the default value. | Keys with a different value on the machine. |
| Hooks | `hooks:` | No change. | Nothing. |

### 4.1 Packages

- **`packages:`** contains Arch packages and AUR packages. If the pacman sync
  databases have the name, the package is an Arch package. If not, the
  package is an AUR package, and yay builds it. The plan shows the source of
  each package.
- **Local packages.** makepkg builds local packages from a PKGBUILD. Do not
  write local packages in `packages:`. When a host includes a module, lodestar
  installs the local package of the module. The PKGBUILD is in one of these
  locations:
  - In the `pkg/` folder of the module. This is for tools with their code in
    this repository: mutectl, spotify-vol, backdrop, logi-smartshift and lodestar.
  - In the git repository of the tool. This is for tools with their own
    repository: awpro and whatdidhesay.
    ```yaml
    # modules/awpro/module.yaml
    pkg:
      git: git@github.com:romain-ncls/awpro.git
      ref: v0.3.0                 # a tag or a commit stays fixed; a branch moves
      path: packaging/arch        # the folder of the PKGBUILD in that repository
    ```
    lodestar fetches the ref with your git credentials into
    `~/.cache/lodestar/src/`. Then makepkg builds the package there. To update
    the tool, change `ref`. When you work on a tool, `git:` can point to your
    local copy of the repository.
- **The PKGBUILD must build from the fetched source.** Then the ref alone sets
  the version. The awpro PKGBUILD downloads a release archive with a checksum.
  Thus each release must change the version and the checksum in the PKGBUILD.
  On `main`, the awpro PKGBUILD still has the version 0.2.1, but the latest
  release is v0.3.0.
- **Private repositories during the install.** The new machine does not have an
  SSH key yet. Thus `lodestar install` does not build the packages that it
  cannot fetch. The plan shows these packages. The first `lodestar apply` after
  you restore your key builds them.
- **lodestar builds a local package again in these conditions:**
  - The `pkg/` folder changed. lodestar keeps the hash of the folder in its
    state file, not in the package.
  - The `ref` changed.
  - The branch of the ref moved.
  - A library that the package uses is not there (refer to Section 4.2).
- **A local package must not have the name of an AUR package.** yay updates
  each installed package that has a higher version in the AUR, also a local
  package. `lodestar check` shows a message when a local package has the name
  of an AUR package or an Arch package. For this reason, we changed the name
  `logi-wheel` to `logi-smartshift`. An AUR package for game wheels has the
  name `logi-wheel`.

### 4.2 Updates

- **One command.** `lodestar upgrade` (abbreviation `lds up`) runs `yay -Syu`
  without the local packages. Then it builds again the local packages that
  must be built again (refer to Section 4.1).
- **No pacman hook from lodestar.** A pacman hook runs as root while pacman
  locks its database. Thus a hook cannot build or install packages. It can
  only show a message. The Arch package `rebuild-detector` already shows the
  necessary message. After each pacman operation, it shows the packages that
  use a library that is not there. The base module installs it. `lodestar
  upgrade` uses its command `checkrebuild` to find the packages to build
  again.
- **This problem has an effect on few of your tools.** The Go tools and awpro
  are static binaries. Thus library updates cannot cause them to fail. Only
  whatdidhesay (Rust with Vulkan) can need a new build.

### 4.3 Files

- **System files.** The owner is root and the mode is 644. If the file is
  executable in git, the mode is 755. To set a different mode, write it in
  `module.yaml`:
  ```yaml
  files:
    /etc/sudoers:
      mode: "0440"                # with quotes: without quotes, YAML reads a number
      check: "visudo -cf {}"
  ```
  The `check` command examines the new file. lodestar replaces the live file
  only if the check is satisfactory.
- **Home files.** lodestar copies home files. It does not make links to the
  repository. Because of this, an application cannot write into the repository
  by accident. Drift also shows changes to the copies. To edit a file at its
  location in the repository, declare a link:
  ```yaml
  # modules/mpv/module.yaml
  files:
    ~/.config/mpv:
      link: config                # relative to the module folder
  ```
- **Follow-up commands.** lodestar runs these commands automatically after it
  changes a related file:
  - `locale-gen` after a change to `/etc/locale.gen`
  - `udevadm control --reload` and `udevadm trigger` after a change to a udev
    rule
  - `systemctl daemon-reload` after a change to a unit file
  - `limine-mkinitcpio` after a change to `mkinitcpio.conf` or
    `kernel/cmdline`
  - `sysctl --system` after a change in `/etc/sysctl.d`

  To run a different command after a change to a file, write
  `then: <command>` for that file.

### 4.4 Units

- `services` enables system units with `systemctl enable`.
- `user-services` enables user units for all users with
  `systemctl --global enable`.

These two commands also operate in the chroot of the installer. A unit
drop-in is a system file, for example
`system/etc/systemd/system/languagetool.service.d/port.conf`.

### 4.5 Firewall

Each module declares the ports that it uses. lodestar makes one nftables
ruleset from these ports. The ruleset stops all the traffic that comes into
the machine, with these exceptions:

- Traffic of connections that are already open
- Loopback traffic and ICMP
- Traffic from the Docker bridges
- Traffic to the declared ports

The ruleset is in a table that lodestar owns. lodestar replaces this table with
`destroy table` and a new definition. lodestar never uses `flush ruleset`.
Because of this, the Docker tables do not change.

Docker sends the traffic for ports that you publish with `-p` before this
ruleset examines it. Thus other machines on the network can connect to a
container that has `-p 5432:5432`. Publish the ports of development containers
on `127.0.0.1` only, for example `-p 127.0.0.1:5432:5432`.

### 4.6 KDE

- **Full files.** If KDE only reads a file, the module keeps the full file.
  Examples are themes (color schemes, Plasma style, global theme, icons,
  cursors), Konsole profiles, `.desktop` entries, KWin scripts and wallpaper
  plugins.
- **Keys.** If KDE also writes a file, the module keeps only the keys that you
  selected. The `*rc` files in `~/.config` are files of this type. They contain
  settings, but also the state of KDE and values for one machine only.
  Examples of state are window sizes, tile layouts and the last tool that you
  used. Examples of values for one machine are input devices and screen
  names. A full copy would reset the state at each apply operation, and two
  hosts could not share it.

  Write the file, the group and the key:
  ```yaml
  kde:
    kwinrc:
      Windows:
        Placement: Centered
    powerdevilrc:
      AC/Display:                 # a / separates nested groups
        DimDisplayWhenIdle: false
  ```
  lodestar reads KDE files with its own parser. Drift is fast because lodestar
  does not start one process for each key. lodestar writes with
  `kwriteconfig6`, the KDE library. It changes only the given key and does the
  KDE escape sequences. The plan shows which changes cause a KWin
  reconfiguration. lodestar starts this reconfiguration automatically. The
  plan also shows which changes become active only after a new login.
- **KDE lists.** Breeze window exceptions and KWin window rules are groups with
  numbers. Two modules cannot use the same fixed numbers. For example, the mpv
  exception in home-arch is "Exception 0". On the laptop, "Exception 0" is the
  Konsole rule. Because of this, lodestar owns the full list. Each module adds
  entries. lodestar gives a number to each entry and removes the entries that
  are not declared.
  ```yaml
  breeze-exceptions:              # in modules/mpv
    - pattern: mpv
      hide-title-bar: true
      border-size: 0
  ```
- **Shortcuts.** A shortcut is in the module that supplies its command. A host
  has the shortcuts of all its modules. Thus, to share a shortcut between two
  hosts, put its module on the two hosts. lodestar writes each custom command
  as a KDE `net.local.*.desktop` entry. System Settings then shows these
  commands in its normal list. You can also change the keys of a KDE action:
  ```yaml
  shortcuts:
    - component: kwin
      action: Window Maximize
      keys:
        - Meta+Up
  ```
- **Changes in System Settings.** After each apply operation, lodestar makes a
  KDE snapshot. `lodestar kde review` shows the keys that changed after the
  snapshot. For each key, select one of these actions:
  - **Keep.** lodestar adds the key to the module or host that you select.
  - **Ignore.** lodestar adds the key to the `kde-ignore:` list of that module.
    lodestar does not show the key again.
  - **Undo.** lodestar writes the old value again.

  `lodestar drift` also counts these keys. A list in lodestar hides the KDE
  state, for example window sizes, tile layouts, recent files and update
  markers. This list will need adjustments during the first weeks. If the list
  does not hide a state key, `kde review` shows it.
- **Find the key for one change.** Do these steps:
  1. Run `lodestar kde watch`. lodestar records the KDE files.
  2. Change the value in System Settings.
  3. Push Enter. lodestar shows the keys that changed, in YAML format.
  4. Copy these lines into a module.
- **The first version does not include the panel layout.** Plasma keeps the
  panel layout in sections with numbers that refer to screen numbers. Thus
  keys and full files are not correct for it. Plasma can change panels with
  scripts through `plasmashell`. A later version can use these scripts.

### 4.7 JSON keys

Some applications write their settings file again when they close, for
example Readest. For these files, lodestar merges the declared keys into the
file:

```yaml
json:
  - path: ~/.config/com.bilingify.readest/settings.json
    merge: readest.json           # relative to the module folder
    unless-running: readest       # Readest writes the file again when it closes
```

### 4.8 Hooks

A hook runs a script. Use a hook only for a task that is not a file or a key.
Two examples are flat mouse acceleration for all mice and the KRDP
certificate.

```yaml
hooks:
  - run: flat-mice                # a script in the module folder
    as: user                      # or root
    when: always                  # or changed: the module changed after the last run
```

## 5. Templates, facts and secrets

A file with the extension `.tmpl` is a Go template. A template can use these
values:

- `.host`, `.vars.*` and `.user.*`.
- **Facts.** lodestar reads the facts from the machine during the apply
  operation. Three examples are `fact "root-luks-uuid"`, `fact "esp-uuid"`
  and `fact "resume-offset"`. `/etc/fstab` and `/etc/kernel/cmdline` are
  templates. Thus the repository contains no UUIDs. A new installation does
  not change the repository.
- **`file "~/.ssh/id_ed25519.pub"`.** This gives the contents of a file. If the
  file is not there, it gives an empty text. The git `allowed_signers` file
  uses it.
- **`bitwarden "item" "field"`.** When a template uses a secret for the first
  time, lodestar runs `bw unlock`. lodestar keeps the session for that
  operation only. The repository never contains secrets. This rule is also
  true for encrypted secrets.

## 6. Commands

| Command | Root | Function |
|---|---|---|
| `lodestar plan` | No | Shows the changes that `lodestar apply` will make. |
| `lodestar apply [--system \| --home]` | One prompt | Makes the machine the same as the repository. |
| `lodestar drift` | No (refer to the note) | Shows all the items that the repository does not declare. The exit code is 1 if it finds an item. |
| `lodestar prune` | One prompt | Shows the explicit packages and the orphans that the repository does not declare. Removes them after you type yes. |
| `lodestar upgrade` | One prompt | Runs `yay -Syu` without the local packages. Then builds again the local packages that must be built again (refer to Section 4.2). |
| `lodestar add <path> [--to <module>]` | No | Copies a live file into a module. |
| `lodestar kde review` | No | Keeps, ignores or undoes each KDE key that changed after the last apply operation (refer to Section 4.6). |
| `lodestar kde watch` | No | Shows the keys that one change in System Settings sets (refer to Section 4.6). |
| `lodestar check [--host <h>]` | No | Examines the configuration of a host without the machine. CI does this check for all the hosts. |
| `lodestar schema` | No | Makes the JSON Schemas in `schema/` again. |
| `lodestar install <host>` | Live USB | Installs a host (refer to Section 9). |

NOTE: lodestar cannot read some files without root, for example `/etc/sudoers`
and `/etc/sudoers.d/`. `lodestar drift` shows the names of these files.
`sudo lodestar drift` also examines their contents.

lodestar finds the repository at `~/dotfiles`. The variable `$LODESTAR_REPO`
can set a different location. lodestar finds the host from the hostname. The
option `--host` can set a different host. The package installs fish
completions and the fish abbreviation `lds`. Thus `lds plan` expands to
`lodestar plan`.

## 7. Sequence of the apply operation

`lodestar apply` does these steps:

1. **Plan, as your user.** lodestar loads the configuration, reads the machine
   and makes the plan. Then it shows the plan. `lodestar plan` stops after
   this step.
2. **Password, one time.** lodestar runs `sudo -v`. It keeps the sudo session
   open until the operation ends.
3. **First snapshot.** snapper makes a "pre" snapshot.
4. **Arch packages, as root.** pacman installs the Arch packages
   (`pacman -S --needed`). The packages come before the files. Because of
   this, pacman does not find a file that no package owns in its path.
5. **AUR and local packages, as your user.** yay builds the AUR packages.
   makepkg builds the local packages that changed. The installation of these
   packages uses the open sudo session.
6. **System configuration, as root.** lodestar writes the system files, the
   units, the user and groups, the firewall and `limine.conf`. Then it runs
   the follow-up commands.
7. **Second snapshot.** snapper makes a "post" snapshot.
8. **Home, as your user.** lodestar writes the home files, the KDE keys, the
   KDE lists, the shortcuts and the JSON keys. Then it runs the hooks. Then it
   makes the KDE snapshot for `lodestar kde review`.

The root steps run as `sudo lodestar`. lodestar sends the plan to this process
on stdin. Thus the root process makes only the changes that the plan shows.
Claude can run `lodestar plan` and `lodestar drift`. Claude cannot run
`lodestar apply`, because it cannot type a password.

## 8. State and removal

lodestar records its changes in two state files:

- `/var/lib/lodestar/state.json` for the system
- `~/.local/state/lodestar/state.json` for the home

For each file that lodestar writes, the state file records three items: the
path, the hash and the module that declares the file. The state file also
records the KDE keys that lodestar set. It also records the hashes of the
hooks and of the local packages. The KDE snapshot is in
`~/.local/state/lodestar/kde/`.

The state file lets lodestar remove an item that you removed from the
repository. It also lets lodestar find the difference between a change on the
machine and a change in the repository.

- **System files.** If a package owns the file, lodestar restores the package
  version from the package cache. If no package owns the file, lodestar
  removes the file.
- **Home files.** lodestar removes the file only if nobody changed it after
  lodestar wrote it. If somebody changed the file, the plan shows a message.
  lodestar then keeps the file.
- **Packages.** `lodestar apply` never removes packages. To try a package,
  install it with `yay -S foo`. `lodestar drift` then shows the package. Add
  the package to a module, or remove it with `lodestar prune`.

## 9. Install

### 9.1 Start the install

**CAUTION:** Make a backup of all the data on the disk before you start.
`lodestar install` erases the full disk.

On the live USB, do these steps:

1. Set the French keymap. The live USB starts with the US keymap.
   ```sh
   loadkeys fr
   ```
2. Connect to the network. You can also connect an Ethernet cable.
   ```sh
   iwctl station wlan0 connect "<SSID>"
   ```
3. Start the install:
   ```sh
   curl -fsSL https://raw.githubusercontent.com/romain-ncls/dotfiles/main/install.sh | bash -s -- wandersail
   ```

No lodestar binary is on the internet. `install.sh` builds lodestar on the live
USB from the repository.

### 9.2 Steps of install.sh

`install.sh` does these steps:

1. **Safe pipe.** The script is one function. The last line of the script
   starts this function. Thus, if the download stops before the end, the
   script does nothing.
2. **Space on the live USB.** The live system writes its changes to a RAM disk
   of 256 MiB. git and Go use approximately 300 MiB. Thus the script makes the
   RAM disk larger: `mount -o remount,size=2G /run/archiso/cowspace`.
3. **Tools.** The script runs `pacman -Sy archlinux-keyring git go`. The ISO
   does not contain git or Go. An old ISO can have an old keyring that refuses
   new packages.
4. **Repository.** The script clones the repository with HTTPS into
   `/root/dotfiles`. The option `--branch <name>` selects a different branch,
   for a test before a merge.
5. **Build.** `go build` makes `/root/lodestar`, a static binary.
6. **Start lodestar.** The script runs
   `lodestar install wandersail --repo /root/dotfiles`, with the terminal as
   its input (`</dev/tty`). In a pipe, the input of bash is the download.
   Without this redirection, lodestar and cryptsetup would read the script as
   your answers and your passphrase.

### 9.3 Steps of lodestar install

lodestar does these steps:

1. **Checks.** lodestar makes sure that these conditions are true:
   - The machine operates from the live USB, in UEFI mode.
   - The network connection operates.
   - The disk is the disk in `install.disk`.

   Then lodestar shows the disk. Type the hostname to continue.
2. **Disk of wandersail.** lodestar makes a GPT partition table with two
   partitions:
   - **ESP.** A FAT32 partition of 4 GiB, mounted on `/boot`. Limine can read
     only FAT. Because of this, the kernels and the snapshot kernels are on
     the ESP.
   - **LUKS2.** A LUKS2 partition on all the other space. lodestar shows a
     prompt for the passphrase. The partition contains btrfs with these
     subvolumes: `@`, `@home`, `@snapshots`, `@var_log`, `@var_cache`,
     `@var_tmp`, `@var_lib_docker` and `@swap`. `@swap` contains a swapfile
     of 32 GiB for hibernation.
3. **Packages.** `pacstrap` installs the Arch packages of the host.
4. **System.** lodestar uses the same code as step 6 of `lodestar apply`, with
   `/mnt` as the root. It writes the files, the units (`systemctl --root`),
   the user and the groups.
   - lodestar reads the facts from the new disk. Thus `fstab` and the kernel
     command line (`rd.luks.name=…`, `resume_offset=…`) are correct
     immediately.
   - The initramfs has the French keymap. Thus you type the passphrase with
     the AZERTY layout.
5. **AUR and local packages.** lodestar builds these packages in the chroot,
   as your user. A temporary sudo rule lets the build install them. lodestar
   always removes this rule after the build, also if the build fails. Packages
   from private repositories wait for the first apply operation (refer to
   Section 4.1).
6. **Boot.** lodestar configures snapper on `@snapshots`. Then it installs
   Limine and enrolls its configuration.
7. **Passwords and repository.** lodestar shows a prompt for your password and
   for the root password. Then it copies the clone, with its history, to
   `~/dotfiles`. It changes the remote of the clone to the SSH URL. Thus you
   can push when your SSH key is ready.

### 9.4 First boot

1. Reboot the machine.
2. Type the LUKS passphrase.
3. Log in.
4. Run `lodestar apply` for the home part.
5. When lodestar prompts for the Bitwarden master password, type it.
6. Restore the data from the backup.

You type only passwords: the LUKS passphrase, your password, the root
password, the Bitwarden master password and the restic password.

If the install stops, you can start it again. This is safe because the install
writes only to the disk that it erases.

## 10. Tests

- **Go tests.** These tests examine the merge of the configuration, the plan on
  a simulated machine, the KDE parser and the templates.
- **CI.** On each push, CI runs `lodestar check` for all the hosts. Thus CI
  finds an incorrect configuration before you apply it to a machine. CI
  publishes nothing. You can remove it.
- **Arch container.** Docker on the laptop applies the system part into a
  temporary Arch root.
- **VM.** The VM is QEMU with UEFI and a blank virtual disk, on the laptop. The
  test does these steps:
  1. The Arch ISO boots with `script=`. Thus it runs `install.sh` with test
     passphrases, without a person. The test uses the same script as a real
     install.
  2. The VM reboots, unlocks the disk and shows the login screen.
  3. The test runs `lodestar apply` and makes a screenshot.

  The VM operates with a memory limit. Only one VM operates at a time.

Do not install on the real disk before the VM test is satisfactory.

## 11. Sequence of the work

1. **Core.** Load the configuration. Make `plan`, `apply`, `drift` and `prune`
   for packages, files, units and the user. Add templates, Bitwarden and the
   state file.
2. **Other resources.** Add KDE keys, KDE lists, shortcuts, `kde review`,
   `kde watch` and the completion from `.kcfg` files. Then add JSON keys,
   hooks, local packages, the firewall and Limine.
3. **home-arch.** Move `system/`, `home/`, `.kde/`, `pkg/`, `scripts/`, `mpv/`
   and `windows/` into hosts and modules. Then `lodestar check --host menadion`
   must pass. The result must be the same as the configuration of menadion.
4. **Host wandersail.** Add these items:
   - The items from the inventory.
   - Your tools as modules with a `pkg/` folder. In these tools, change
     `qdbus` to `qdbus6`.
   - awpro and whatdidhesay with `pkg: git:`. Their PKGBUILDs must build from
     the source.
   - The KDE settings from KDE.md.
5. **Install.** Make `lodestar install` and the VM test. Do the test again
   until a new installation is correct.
6. **Migration of wandersail.** Do the checklist for the disk erasure. Make
   the last backup. Do the install and the restore.
7. **menadion, at home.** `lodestar plan` must show no changes. Then remove
   aconfmgr, chezmoi and `just`. On Windows, run `Setup-Mpv.ps1` again one
   time. Then `%APPDATA%\mpv` points to `modules\mpv\config`.

## 12. Implementation

- **Language.** lodestar is in Go. It uses the standard library first. The
  main dependencies are a YAML parser and a JSON Schema generator. The YAML
  parser (`goccy/go-yaml`) shows errors with the file, the line and the
  column. The schema generator (`invopop/jsonschema`) reads the Go types. The
  build makes a static binary (`CGO_ENABLED=0`).
- **External tools.** lodestar runs the correct tool for each task: pacman,
  yay, makepkg, systemctl, kwriteconfig6, nft, cryptsetup, sgdisk, btrfs,
  snapper and bw.
- **Package.** The source of lodestar is in `modules/lodestar/pkg/`. Thus
  lodestar installs a new version of itself when its source changes.
- **Size.** Approximately 3000 to 5000 lines.

## 13. Decisions

| # | Item | Decision | Reason |
|---|---|---|---|
| 1 | Names | The tool is `lodestar` (abbreviation `lds`). The laptop is `wandersail`. | They come from the Cosmere books. A lodestar moves the controls of its owner into each machine. The Wandersail is the ship of Rysn. |
| 2 | Configuration language | YAML data, with a JSON Schema that lodestar makes from its Go types. Templates and hooks for special cases. | VS Code completes and examines the files. YAML is lighter than TOML. The logic stays in Go, where tests can examine it. |
| 3 | Package sources | One `packages` list. lodestar finds the source. Local packages come from the modules. | If a package moves between the AUR and the sync databases, the repository does not change. The plan shows the source. |
| 4 | Removal | `apply` never removes packages. `prune` removes them. lodestar removes the files and keys that it wrote when you remove their declaration. | A package test stays easy. The repository stays the reference for the configuration. |
| 5 | Home files | Copies. Links only when declared, for example mpv and the wallpaper development. | Applications cannot write into the repository. Drift shows changes. |
| 6 | KDE | Full files for the files that KDE only reads. Keys for the files that KDE also writes. lodestar owns the lists of exceptions and window rules. Shortcuts are in modules. `kde review` keeps the changes from System Settings. | The KDE rc files contain state and values for one machine. This removes the number conflict. The modules set which shortcuts the hosts share. |
| 7 | AUR | yay | yay already resolves the AUR dependencies. |
| 8 | Source of the tool | In this repository (`modules/lodestar/pkg/`). `install.sh` builds it on the live USB. No binary on the internet. | One commit can change the tool and the configuration together. One command starts an install. |
| 9 | Firewall | nftables, in a table that lodestar owns. The ruleset accepts the traffic from the Docker bridges. | The Docker rules stay. A port is one line in a module. |
| 10 | Snapshots | A snapper snapshot before and after each apply operation. | One rollback can undo an incorrect apply operation. |
| 11 | Disk of wandersail | An ESP of 4 GiB. LUKS2 with btrfs and a swapfile of 32 GiB. A passphrase unlocks the disk. | Hibernation operates without a second LUKS volume. A TPM2 key can come later without a new installation. |
| 12 | Layout | One folder for each host and each module, with the same layout. lodestar installs only `system/` and `home/`. The package of a tool is in the `pkg/` folder of its module. mpv is a module. | All the parts of one item are in one folder. lodestar does not install a file by accident. |
| 13 | Tools with their own repository | `pkg: git:` with a fixed ref. The PKGBUILD of the tool builds from that source. Private repositories wait for the first apply operation after the install. | The repository of the tool is the only copy of its PKGBUILD. An update is one line. |
| 14 | Updates | `lodestar upgrade` runs `yay -Syu` and builds the local packages again. `rebuild-detector`, not a hook from lodestar. | A pacman hook cannot build packages. The Arch tool already shows the message. |
