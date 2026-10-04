#!/usr/bin/env bash
# Reinstall Arch on the home PC (MENADION) from the Arch live USB.
#
# Disk: WD SN750 1 TB, /dev/nvme0n1, shared with Windows 11.
#   p1  ESP 4 GiB, shared: kept; only the previous Arch files on it are removed
#   p2  MSR, p3 Windows C:, p4 WinRE: never touched
#   p5  Arch root, btrfs: reformatted
#   p6  swap: reformatted
# p5 and p6 are recreated with the UUIDs that system/files/hosts/home/etc/fstab
# and etc/kernel/cmdline already reference, so the repo needs no edit.
#
# Usage, from the live USB (see install/README.md):
#   bash install/menadion.sh
source "$(dirname "$0")/lib.sh"

HOST=menadion
ROLE=home
USERNAME=romain
DISK=/dev/nvme0n1
ESP=${DISK}p1
ROOT=${DISK}p5
SWAP=${DISK}p6
WINDOWS=${DISK}p3

FSTAB=$SYS/files/hosts/home/etc/fstab
ROOT_UUID=$(awk '$2 == "/"    { sub(/^UUID=/, "", $1); print $1 }' "$FSTAB")
SWAP_UUID=$(awk '$3 == "swap" { sub(/^UUID=/, "", $1); print $1 }' "$FSTAB")
ESP_UUID=$(awk '$2 == "/boot" { sub(/^UUID=/, "", $1); print $1 }' "$FSTAB")

ESP_GUID=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
LINUX_GUID=0fc63daf-8483-4772-8e79-3d69d8477de4
SWAP_GUID=0657fd6d-a4ab-43c4-84e5-0933c84b4f4f

need_live_usb

# ── check this really is MENADION's disk, before anything is written ────
say "Checking $DISK"
for dev in "$ESP" "$ROOT" "$SWAP" "$WINDOWS"; do [[ -b $dev ]] || die "$dev does not exist"; done
[[ $(lsblk -dno PARTTYPE "$ESP")  == "$ESP_GUID" ]]   || die "$ESP is not an EFI system partition"
[[ $(lsblk -dno PARTTYPE "$ROOT") == "$LINUX_GUID" ]] || die "$ROOT is not a Linux filesystem partition"
[[ $(lsblk -dno PARTTYPE "$SWAP") == "$SWAP_GUID" ]]  || die "$SWAP is not a Linux swap partition"
[[ $(lsblk -dno UUID "$ESP") == "$ESP_UUID" ]]        || die "$ESP's UUID is not the one in the repo's fstab ($ESP_UUID)"
[[ $(lsblk -dno FSTYPE "$WINDOWS") == ntfs ]]         || die "$WINDOWS is not Windows' NTFS partition"
[[ -n $ROOT_UUID && -n $SWAP_UUID ]]                  || die "could not read the root/swap UUIDs from $FSTAB"
mkdir -p /tmp/esp
mount -o ro "$ESP" /tmp/esp
[[ -f /tmp/esp/EFI/Microsoft/Boot/bootmgfw.efi ]] || { umount /tmp/esp; die "Windows' boot manager is not on $ESP"; }
umount /tmp/esp
ok "ESP with Windows' boot manager, Linux root and swap partitions, Windows on p3"

confirm "This ERASES $ROOT (Arch root) and $SWAP (swap). The ESP, Windows (p2-p4) and the partition table are not touched."

# ── format p5/p6 with the repo's UUIDs ──────────────────────────────────
say "Formatting $ROOT and $SWAP"
swapoff -a
wipefs -a "$ROOT" "$SWAP"
mkfs.btrfs -q -f -L arch -U "$ROOT_UUID" "$ROOT"
mkswap -q -L swap -U "$SWAP_UUID" "$SWAP"
ok "btrfs $ROOT_UUID, swap $SWAP_UUID"

make_subvolumes "$ROOT"
mount_tree "$ROOT" "$ESP" "$SWAP"

# ── remove the previous Arch install's files from the shared ESP ────────
# Only Arch's own files: kernels/initramfs per machine-id, limine.conf and
# the loose kernel files. EFI/Microsoft and EFI/BOOT stay; EFI/limine is
# rewritten by limine-install.
say "Removing the previous Arch install's files from the ESP"
find "$T/boot" -maxdepth 1 -type d -regextype egrep -regex '.*/[0-9a-f]{32}' -exec rm -rf {} +
rm -f "$T"/boot/limine.conf "$T"/boot/limine.conf.* "$T"/boot/vmlinuz-linux \
	"$T"/boot/initramfs-linux*.img "$T"/boot/intel-ucode.img
ls "$T/boot" "$T/boot/EFI"

pacstrap_repo_packages
materialize_system
base_setup
aur_packages
snapper_setup "$ROOT"
copy_repo
limine_setup
finish
