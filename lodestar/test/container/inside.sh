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
# the user exists with KDE state lodestar must keep
useradd -m -s /bin/bash romain
runuser -u romain -- mkdir -p /home/romain/.config/app
runuser -u romain -- sh -c "printf '[Common]\nShadowSize=2\n\n[Windeco Exception 0]\nExceptionPattern=konsole\n' >/home/romain/.config/breezerc"
runuser -u romain -- sh -c "printf '{\"keep\": 1, \"reader\": {\"font\": \"Lato\", \"margin\": 10}}\n' >/home/romain/.config/app/settings.json"
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
ok "user's shell and groups set"
[[ $(stat -c %U /home/romain/.config/fish/config.fish) == romain ]] || fail "home file owner $(stat -c %U /home/romain/.config/fish/config.fish)"
[[ $(stat -c %U /home/romain/.config/fish) == romain ]] || fail "home dir owner"
ok "home file and its folders belong to romain"
[[ -L /etc/systemd/system/timers.target.wants/fstrim.timer ]] || fail "fstrim.timer not enabled"
ok "unit enabled"
[[ -s /var/lib/lodestar/state.json && -s /home/romain/.local/state/lodestar/state.json ]] || fail "state files"
ok "state files written"

say "checks: KDE, shortcuts, JSON, hooks, local package, firewall"
cfg=/home/romain/.config
grep -qx 'Placement=Centered' $cfg/kwinrc && grep -qx 'BlurStrength=11' $cfg/kwinrc || fail "kwinrc: $(cat $cfg/kwinrc)"
grep -q '^\[AC\]\[Display\]' $cfg/powerdevilrc || fail "powerdevilrc nested group: $(cat $cfg/powerdevilrc)"
[[ $(stat -c %U $cfg/kwinrc) == romain ]] || fail "kwinrc owner"
ok "KDE keys written with kwriteconfig6, owned by romain"
grep -q 'ShadowSize=2' $cfg/breezerc && grep -q 'ExceptionPattern=mpv' $cfg/breezerc || fail "breezerc: $(cat $cfg/breezerc)"
grep -q konsole $cfg/breezerc && fail "the old exception is still there"
ok "Breeze exceptions replaced, other Breeze settings kept"
grep -q '^Order=1$' $cfg/kwinrulesrc && grep -q 'wmclass=discord' $cfg/kwinrulesrc || fail "kwinrulesrc: $(cat $cfg/kwinrulesrc)"
ok "window rules"
desk=/home/romain/.local/share/applications/net.local.lodestar-mute.desktop
grep -q 'X-KDE-GlobalAccel-CommandShortcut=true' $desk || fail "shortcut desktop file"
grep -A1 'net.local.lodestar-mute.desktop' $cfg/kglobalshortcutsrc | grep -qx '_launch=Meta+M' || fail "kglobalshortcutsrc: $(cat $cfg/kglobalshortcutsrc)"
grep -qx 'Window Maximize=Meta+Up,none,Window Maximize' $cfg/kglobalshortcutsrc || fail "action shortcut: $(cat $cfg/kglobalshortcutsrc)"
ok "shortcuts: command and action"
s=$cfg/app/settings.json
[[ $(jq -c . $s) == '{"keep":1,"reader":{"font":"Literata","margin":10,"size":40},"theme":"contrast"}' ]] || fail "json: $(jq -c . $s)"
ok "JSON keys merged, others kept"
[[ $(cat /home/romain/hook-ran) == romain && $(cat /root/root-hook-ran) == root ]] || fail "hooks"
ok "user hook ran as romain, root hook as root"
pacman -Q lodestar-test-tool >/dev/null && [[ $(lodestar-test-tool) == tool ]] || fail "local package"
[[ ! -e /etc/sudoers.d/00-lodestar-build ]] || fail "the temporary sudo rule is still there"
ok "local package built and installed; temporary sudo rule removed"
grep -q 'tcp dport { 1714-1764 } accept' /etc/nftables.conf && grep -q 'udp dport { 1714-1764, 5353 } accept' /etc/nftables.conf || fail "nftables.conf: $(cat /etc/nftables.conf)"
[[ -L /etc/systemd/system/multi-user.target.wants/nftables.service ]] || fail "nftables.service not enabled"
ok "firewall ruleset written (checked by nft) and enabled"

say "second plan: nothing to do"
out=$(ls_ plan)
echo "$out"
[[ $out == "Nothing to do"* ]] || fail "second plan is not empty"
ok "idempotent"

say "drift"
ls_ drift || fail "drift is not clean after apply"
ok "no drift after apply"
echo by-hand >/etc/by-hand.conf
pacman -S --noconfirm tree >/dev/null
if out=$(ls_ drift); then fail "drift should report the changes"; fi
echo "$out"
grep -q /etc/by-hand.conf <<<"$out" && grep -qw tree <<<"$out" || fail "drift misses the changes"
ok "drift reports a file and a package installed by hand"
ls_ prune --yes
pacman -Q tree >/dev/null 2>&1 && fail "prune left tree installed"
pacman -Q sudo >/dev/null || fail "prune removed a declared package"
ok "prune removed only the undeclared package"
rm /etc/by-hand.conf

say "as the user, through sudo"
# verifypw=any: sudo -v would still ask, because 10-wheel's rule has a password
printf 'Defaults:romain verifypw=any\nromain ALL=(ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/99-test
chmod 440 /etc/sudoers.d/99-test
printf 'test\n' >/repo/modules/base/system/etc/issue
mkdir -p /repo/modules/shell/home/.config/test && printf 'x\n' >/repo/modules/shell/home/.config/test/x
su -s /bin/bash romain -c "lodestar apply --yes --repo /repo --host box"
[[ $(stat -c %U /etc/issue) == root && $(cat /etc/issue) == test ]] || fail "/etc/issue through sudo"
[[ $(stat -c %U /home/romain/.config/test/x) == romain ]] || fail "home file as the user"
grep -q '"/etc/issue"' /var/lib/lodestar/state.json || fail "system state not updated by the root process"
ok "root part through sudo, home part as the user"
rm /repo/modules/base/system/etc/issue /repo/modules/shell/home/.config/test/x

say "drop a KDE key and a shortcut"
sed -i '/BlurStrength/d; /Effect-blur/d' /repo/modules/desktop/module.yaml
sed -i '/- name: Mute/,+2d' /repo/modules/desktop/module.yaml
ls_ apply --yes
grep -q BlurStrength $cfg/kwinrc && fail "BlurStrength still set"
[[ -e $desk ]] && fail "shortcut desktop file still there"
grep -q 'lodestar-mute' $cfg/kglobalshortcutsrc && fail "shortcut key still there"
ok "dropped KDE key deleted, dropped shortcut removed"
out=$(ls_ plan)
[[ $out == "Nothing to do"* ]] || { echo "$out"; fail "plan after KDE removals is not empty"; }

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
