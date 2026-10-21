#!/usr/bin/env bash
# Runs inside the container (as root), from test/container.sh.
set -euo pipefail

say()  { printf '\n\033[1;36m### %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31mFAIL: %s\033[0m\n' "$*"; exit 1; }
ok()   { printf '\033[32mok: %s\033[0m\n' "$*"; }
ls_() { lodestar "$@" --repo /repo --host box; }

say "setup"
pacman-key --init >/dev/null 2>&1
pacman-key --populate archlinux >/dev/null 2>&1
pacman -Sy --noconfirm >/dev/null
cp -a /repo-src /repo
ln -sf /usr/share/zoneinfo/UTC /etc/localtime   # a file no package owns, replaced then given back
orig_localtime=$(readlink /etc/localtime)

say "first plan"
ls_ plan
ls_ check

say "apply"
ls_ apply --yes

say "checks"
pacman -Q sudo fish >/dev/null && ok "packages installed"
[[ $(pacman -Qqe | grep -cx 'sudo\|fish') == 2 ]] && ok "installed as explicit"
[[ $(stat -c %a /etc/sudoers.d/10-wheel) == 440 ]] || fail "sudoers.d mode $(stat -c %a /etc/sudoers.d/10-wheel)"
ok "sudoers.d mode 0440"
[[ $(cat /etc/motd) == "Welcome to box, romain." ]] || fail "motd: $(cat /etc/motd)"
ok "template rendered"
[[ $(readlink /etc/localtime) == /usr/share/zoneinfo/Europe/Paris ]] || fail "localtime -> $(readlink /etc/localtime)"
ok "link"
grep -q 'managed by lodestar' /etc/bash.bashrc && ok "package file replaced"
[[ $(getent passwd romain | cut -d: -f7) == /usr/bin/fish ]] || fail "shell"
id -nG romain | grep -qw wheel || fail "groups: $(id -nG romain)"
ok "user created with shell and groups"
[[ $(stat -c %U /home/romain/.config/fish/config.fish) == romain ]] || fail "home file owner $(stat -c %U /home/romain/.config/fish/config.fish)"
[[ $(stat -c %U /home/romain/.config/fish) == romain ]] || fail "home dir owner"
ok "home file and its folders belong to romain"
[[ -L /etc/systemd/system/timers.target.wants/fstrim.timer ]] || fail "fstrim.timer not enabled"
ok "unit enabled"
[[ -s /var/lib/lodestar/state.json && -s /home/romain/.local/state/lodestar/state.json ]] || fail "state files"
ok "state files written"

say "second plan: nothing to do"
out=$(ls_ plan)
echo "$out"
[[ $out == "Nothing to do"* ]] || fail "second plan is not empty"
ok "idempotent"

say "drop files from the repo"
rm /repo/modules/base/system/etc/bash.bashrc /repo/modules/base/system/etc/localtime
rm /repo/modules/shell/home/.config/fish/config.fish
sed -i '/fstrim.timer/d; /^services:$/d' /repo/modules/base/module.yaml
ls_ plan
ls_ apply --yes
grep -q 'managed by lodestar' /etc/bash.bashrc && fail "bash.bashrc not restored"
pacman -Qkk bash 2>&1 | grep -q '/etc/bash.bashrc' && fail "bash.bashrc differs from the package"
ok "package file restored from the archive"
[[ $(readlink /etc/localtime || echo none) == "$orig_localtime" ]] || fail "localtime -> $(readlink /etc/localtime)"
ok "original link restored ($orig_localtime)"
[[ ! -e /home/romain/.config/fish/config.fish ]] || fail "home file still there"
ok "home file removed"
[[ ! -e /etc/systemd/system/timers.target.wants/fstrim.timer ]] || fail "fstrim.timer still enabled"
ok "unit disabled"
out=$(ls_ plan)
[[ $out == "Nothing to do"* ]] || { echo "$out"; fail "plan after removals is not empty"; }
ok "idempotent after removals"

say "a failing check leaves the live file alone"
echo 'this is not sudoers syntax (' >/repo/modules/base/system/etc/sudoers.d/10-wheel
if ls_ apply --yes; then fail "apply should have failed"; fi
grep -q '^%wheel' /etc/sudoers.d/10-wheel || fail "sudoers.d was changed"
ls /etc/sudoers.d | grep -q lodestar && fail "temporary file left behind"
ok "check refused the file, nothing left behind"

say "all good"
