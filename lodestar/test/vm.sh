#!/usr/bin/env bash
# Installs a host in a QEMU VM from the Arch ISO, unattended, through the same
# install.sh as a real install; then boots the installed disk, unlocks it and
# takes screenshots.
#
#   test/vm.sh install [host]   fresh disk, install (default host: vm)
#   test/vm.sh boot             boot the installed disk
#
# Needs qemu (with its edk2 firmware), bsdtar, python3 and KVM. The ISO, the
# disk and the logs live in ~/.cache/lodestar-vm. It installs the commits of
# the current branch (not uncommitted changes). Passphrase and passwords:
# lodestar.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
work=${LODESTAR_VM_DIR:-$HOME/.cache/lodestar-vm}
port=${LODESTAR_VM_PORT:-8137}
secret=lodestar
mkdir -p "$work"

say() { printf '\n\033[1;36m### %s\033[0m\n' "$*"; }

firmware() {
	local share
	share=$(dirname "$(readlink -f "$(command -v qemu-system-x86_64)")")/../share/qemu
	code=$share/edk2-x86_64-code.fd
	[[ -f $code ]] || { echo "no edk2 firmware in $share" >&2; exit 1; }
	[[ -f $work/vars.fd ]] || cp "$share/edk2-i386-vars.fd" "$work/vars.fd"
	chmod u+w "$work/vars.fd"
}

# qemu with the disk, UEFI and a monitor socket; extra arguments appended.
vm() {
	firmware
	rm -f "$work/monitor.sock"
	systemd-run --user --scope --quiet -p MemoryMax=8G \
		qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 6G -machine q35 \
		-drive if=pflash,format=raw,readonly=on,file="$code" \
		-drive if=pflash,format=raw,file="$work/vars.fd" \
		-drive file="$work/disk.qcow2",if=none,id=disk,format=qcow2 \
		-device virtio-blk-pci,drive=disk,serial=lodestar-vm \
		-nic user,model=virtio-net-pci \
		-vga virtio -display none \
		-monitor unix:"$work/monitor.sock",server,nowait \
		"$@"
}

monitor() { # send one monitor command
	python3 -c 'import socket,sys,time
s=socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); time.sleep(0.2); s.recv(4096)
s.sendall((sys.argv[2]+"\n").encode()); time.sleep(0.3); s.close()' "$work/monitor.sock" "$1"
}

type_text() { # type a word and Enter on the VM's keyboard
	local c
	for ((i = 0; i < ${#1}; i++)); do
		c=${1:i:1}
		monitor "sendkey $c"
	done
	monitor "sendkey ret"
}

shot() { monitor "screendump $work/$1.png -f png"; echo "screenshot: $work/$1.png"; }

install() {
	local host=${1:-vm} branch iso uuid
	branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD)
	iso=$work/archlinux-x86_64.iso

	say "Arch ISO"
	if [[ ! -f $iso ]]; then
		curl -fL --output "$iso.part" https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso
		curl -fsSL https://geo.mirror.pkgbuild.com/iso/latest/sha256sums.txt | grep 'archlinux-x86_64.iso$' |
			sed "s|archlinux-x86_64.iso|$iso.part|" | sha256sum -c
		mv "$iso.part" "$iso"
	fi
	uuid=$(blkid -s UUID -o value "$iso")
	bsdtar -xf "$iso" -C "$work" --strip-components 3 arch/boot/x86_64/vmlinuz-linux arch/boot/x86_64/initramfs-linux.img

	say "Serving the repo ($branch) and the test script on port $port"
	rm -rf "$work/http" && mkdir -p "$work/http"
	git clone --quiet --bare --branch "$branch" "$repo" "$work/http/dotfiles.git"
	git -C "$work/http/dotfiles.git" update-server-info
	git -C "$repo" show "$branch:install.sh" >"$work/http/install.sh"
	cat >"$work/http/test.sh" <<EOF
#!/bin/bash
exec > >(tee /dev/ttyS0) 2>&1
export LODESTAR_TEST_PASSPHRASE=$secret LODESTAR_TEST_PASSWORD=$secret
if curl -fsSL http://10.0.2.2:$port/install.sh | bash -s -- --repo-url http://10.0.2.2:$port/dotfiles.git --branch $branch --yes $host; then
	echo LODESTAR-INSTALL-OK
else
	echo LODESTAR-INSTALL-FAILED
fi
sleep 3
systemctl poweroff
EOF
	python3 -m http.server "$port" --bind 0.0.0.0 --directory "$work/http" >"$work/http.log" 2>&1 &
	local server=$!
	trap 'kill $server 2>/dev/null' EXIT

	say "Installing $host (log: $work/install.log)"
	rm -f "$work/disk.qcow2" "$work/vars.fd"
	qemu-img create -q -f qcow2 "$work/disk.qcow2" 60G
	vm -cdrom "$iso" -kernel "$work/vmlinuz-linux" -initrd "$work/initramfs-linux.img" \
		-append "archisobasedir=arch archisosearchuuid=$uuid script=http://10.0.2.2:$port/test.sh" \
		-serial file:"$work/install.log"
	if grep -q LODESTAR-INSTALL-OK "$work/install.log"; then
		say "Install OK"
	else
		say "Install FAILED"
		tail -40 "$work/install.log"
		exit 1
	fi
}

boot() {
	say "Booting the installed disk"
	vm -serial file:"$work/boot.log" &
	local qemu=$!
	sleep 20
	shot boot-1-passphrase
	type_text "$secret"
	sleep 60
	shot boot-2-login
	monitor quit
	wait $qemu || true
}

case ${1:-} in
install) shift; install "$@" ;;
boot) boot ;;
*) echo "usage: test/vm.sh install [host] | boot" >&2; exit 2 ;;
esac
