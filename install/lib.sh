# Shared install steps, sourced by install/<host>.sh from the Arch live USB.
# Everything comes from the repo: packages, files, modes and unit links are
# read from system/*.sh with the same per-host guards aconfmgr uses, so the
# installed system already matches `just apply-system`.
#
# The host script sets, before calling these:
#   HOST        hostname, e.g. menadion (system/*.sh guards test it)
#   ROLE        chezmoi role and system/limine/<role>.conf: home | work
#   USERNAME    the login user
# and the devices it formats and mounts.

set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SYS=$REPO/system
T=/mnt
SUBVOLS=(@ @home @snapshots @var_log @var_cache @var_tmp)
BTRFS_OPTS=noatime,compress=zstd:3,ssd,discard=async

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m    ✓ %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m    ✗ %s\033[0m\n' "$*" >&2; exit 1; }
in_target() { arch-chroot "$T" "$@"; }

need_live_usb() {
	[[ $EUID -eq 0 ]] || die "Run as root on the Arch live USB."
	[[ -d /run/archiso ]] || die "This is not the Arch live USB. Refusing to run on an installed system."
	[[ -d /sys/firmware/efi/efivars ]] || die "Not booted in UEFI mode."
	mountpoint -q "$T" && die "$T is already mounted; unmount it first (umount -R $T)."
	return 0
}

# Ask for the hostname to be typed back before anything destructive.
confirm() {
	lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTTYPENAME,MOUNTPOINTS
	printf '\n\033[1;31m%s\033[0m\n' "$1"
	read -rp "Type the hostname ($HOST) to continue: " answer
	[[ $answer == "$HOST" ]] || die "Aborted; nothing was changed."
}

# btrfs subvolumes on an already formatted device, then mount the tree.
make_subvolumes() { # ROOT_DEV
	mount "$1" "$T"
	for sv in "${SUBVOLS[@]}"; do btrfs subvolume create "$T/$sv" >/dev/null; done
	umount "$T"
	ok "subvolumes: ${SUBVOLS[*]}"
}

mount_tree() { # ROOT_DEV ESP_DEV SWAP_DEV — @snapshots is mounted later, after snapper
	mount -o "$BTRFS_OPTS,subvol=@" "$1" "$T"
	mkdir -p "$T"/{home,.snapshots,var/log,var/cache,var/tmp,boot}
	mount -o "$BTRFS_OPTS,subvol=@home" "$1" "$T/home"
	mount -o "$BTRFS_OPTS,subvol=@var_log" "$1" "$T/var/log"
	mount -o "$BTRFS_OPTS,subvol=@var_cache" "$1" "$T/var/cache"
	mount -o "$BTRFS_OPTS,subvol=@var_tmp" "$1" "$T/var/tmp"
	mount -o fmask=0077,dmask=0077 "$2" "$T/boot"
	swapon "$3"
	ok "mounted under $T"
}

# Packages system/*.sh declares for $HOST: `packages --native` / `--foreign`.
packages() { HOSTNAME=$HOST "$REPO/scripts/aconf-packages" "$@"; }

pacstrap_repo_packages() {
	say "Installing repository packages from system/*.sh"
	cp "$SYS/files/etc/pacman.conf" /etc/pacman.conf   # [multilib], needed for lib32-*
	pacman -Sy --needed --noconfirm archlinux-keyring
	mapfile -t pkgs < <(packages --native)
	pacstrap -K "$T" "${pkgs[@]}"
	ok "${#pkgs[@]} packages"
}

# Copy files, create unit links and set modes exactly as system/*.sh declares.
# A file without an explicit mode keeps the mode its package gave it (644 if new),
# which is what aconfmgr does too: /etc/sudoers must stay 0440.
materialize_system() {
	say "Writing system files and unit links from system/*.sh"
	(
		put() { # SRC DST MODE
			local mode=$3
			[[ -n $mode ]] || mode=$(stat -c %a "$T$2" 2>/dev/null || echo 644)
			install -D -m "$mode" "$SYS/files$1" "$T$2"
		}
		CopyFile()   { put "$1" "$1" "${2:-}"; }
		CopyFileTo() { put "$1" "$2" "${3:-}"; }
		CreateLink() { mkdir -p "$(dirname "$T$1")"; ln -sfn "$2" "$T$1"; }
		CreateDir()  { install -d -m "${2:-755}" "$T$1"; }
		CreateFile() { install -D -m "${2:-644}" /dev/stdin "$T$1"; }
		SetFileProperty() {
			case $2 in
			mode)  chmod "$3" "$T$1" ;;
			owner) in_target chown "$3" "$1" ;;
			group) in_target chgrp "$3" "$1" ;;
			esac
		}
		AddPackage() { :; }; RemovePackage() { :; }; IgnorePackage() { :; }
		IgnorePath() { :; }; RemoveFile() { :; }
		HOSTNAME=$HOST
		for f in "$SYS"/*.sh; do
			# shellcheck source=/dev/null
			source "$f"
		done
	)
	mkdir -p "$T/mnt/win"
	ok "files copied"
}

base_setup() {
	say "Locale, clock, users"
	in_target locale-gen
	in_target hwclock --systohc   # RTC in UTC; Windows syncs itself over NTP (docs/manual-steps.md)
	in_target useradd -m -G wheel -s /usr/bin/fish "$USERNAME"
	echo "Password for $USERNAME:"
	until in_target passwd "$USERNAME"; do :; done
	echo "Password for root:"
	until in_target passwd root; do :; done
}

# AUR packages are built inside the target as the user, with a temporary
# passwordless sudo that is removed again whatever happens.
aur_packages() {
	say "Building AUR packages (yay first, then the rest)"
	local tmp=$T/etc/sudoers.d/00-install-temporary status=0
	echo "$USERNAME ALL=(ALL:ALL) NOPASSWD: ALL" >"$tmp"
	chmod 440 "$tmp"
	# pkg/ holds local packages: built from the repo by scripts/local-pkgs, not from the AUR
	mapfile -t aur < <(packages --foreign | grep -vx yay | grep -vxF -f <(ls "$REPO/pkg"))
	rm -rf "$T/var/tmp/local-pkgs"   # not /tmp: arch-chroot mounts a fresh tmpfs there
	cp -r "$REPO/pkg" "$T/var/tmp/local-pkgs"
	cp "$REPO/scripts/local-pkgs" "$T/var/tmp/local-pkgs/build"
	in_target runuser -u "$USERNAME" -- env HOME="/home/$USERNAME" bash -euc '
		cd "$(mktemp -d)"
		git clone --depth 1 https://aur.archlinux.org/yay.git
		cd yay && makepkg -sir --noconfirm
		yay -S --needed --noconfirm --removemake "$@"
		PKGROOT=/var/tmp/local-pkgs /var/tmp/local-pkgs/build
	' _ "${aur[@]}" || status=$?
	rm -f "$tmp"   # whatever happened above
	rm -rf "$T/var/tmp/local-pkgs"
	((status == 0)) || die "AUR build failed (exit $status); the temporary sudo rule was removed."
	ok "AUR: yay ${aur[*]}; local: $(ls "$REPO/pkg" | xargs)"
}

# Snapper creates its own .snapshots subvolume inside @; swap it for @snapshots
# and keep the repo's config (create-config refuses to run if it exists).
snapper_setup() { # ROOT_DEV
	say "Snapper"
	local repo_cfg=/etc/snapper/configs/root
	rmdir "$T/.snapshots"   # create-config refuses to run if it exists
	mv "$T$repo_cfg" "$T$repo_cfg.repo"
	in_target snapper --no-dbus -c root create-config /
	mv "$T$repo_cfg.repo" "$T$repo_cfg"
	in_target btrfs subvolume delete /.snapshots >/dev/null
	mkdir "$T/.snapshots"
	mount -o "$BTRFS_OPTS,subvol=@snapshots" "$1" "$T/.snapshots"
	chmod 750 "$T/.snapshots"
	ok "root config on @snapshots"
}

# Limine: EFI binary + NVRAM entry, then limine.conf = repo part + generated part.
limine_setup() {
	say "Limine"
	local machine_id repo=/home/$USERNAME/dotfiles   # copy_repo runs first
	in_target systemd-machine-id-setup >/dev/null
	machine_id=$(cat "$T/etc/machine-id")
	# Seed the OS entry limine-entry-tool fills in (as on the first install),
	# build the initramfs and kernel entries, then let scripts/limine-conf add
	# the repo's globals and hand-written entries and re-enroll with limine-update.
	printf '/Arch Linux\n    comment: machine-id=%s\n' "$machine_id" >"$T/boot/limine.conf"
	in_target limine-install
	in_target limine-mkinitcpio
	in_target "$repo/scripts/limine-conf" apply "$repo/system/limine/$ROLE.conf"
	in_target grep -E '^/' /boot/limine.conf
	ok "limine.conf written and enrolled"
}

copy_repo() {
	say "Copying the repo to /home/$USERNAME/dotfiles"
	cp -a "$REPO" "$T/home/$USERNAME/dotfiles"
	in_target chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/dotfiles"
	ok "done"
}

finish() {
	say "Unmounting"
	sync
	umount -R "$T"
	swapoff -a
	ok "Installed. Remove the USB stick and reboot; then follow install/README.md, 'After the first boot'."
}
