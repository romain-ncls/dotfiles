# Home PC (MENADION) only: NVIDIA, dual-boot with Windows, 4K TV.
# Host-specific files live under files/hosts/home/ and are copied with CopyFileTo.
[[ $HOSTNAME == menadion ]] || return 0

host() { CopyFileTo "/hosts/home$1" "$1" "${@:2}"; }

# ── NVIDIA (RTX 3070 Ti) ────────────────────────────────────────────────
AddPackage nvidia-open-dkms
AddPackage nvidia-utils
AddPackage lib32-nvidia-utils
AddPackage nvidia-settings
AddPackage egl-wayland
host /etc/modprobe.d/nvidia.conf           # PreserveVideoMemoryAllocations=1
CreateLink /etc/systemd/system/systemd-suspend.service.wants/nvidia-suspend.service /usr/lib/systemd/system/nvidia-suspend.service
CreateLink /etc/systemd/system/systemd-suspend.service.wants/nvidia-resume.service /usr/lib/systemd/system/nvidia-resume.service
CreateLink /etc/systemd/system/systemd-hibernate.service.wants/nvidia-hibernate.service /usr/lib/systemd/system/nvidia-hibernate.service
CreateLink /etc/systemd/system/systemd-hibernate.service.wants/nvidia-resume.service /usr/lib/systemd/system/nvidia-resume.service
CreateLink /etc/systemd/system/systemd-suspend-then-hibernate.service.wants/nvidia-resume.service /usr/lib/systemd/system/nvidia-resume.service

# ── identity, disks, boot ───────────────────────────────────────────────
host /etc/hostname
host /etc/hosts
host /etc/fstab                            # btrfs subvolumes, shared ESP, swap, C: (ntfs)
host /etc/kernel/cmdline                   # root + resume UUIDs, nvidia_drm.modeset=1
# MODULES=(btrfs hid_logitech_dj hid_logitech_hidpp): no NVIDIA here, see docs/decisions.md
host /etc/mkinitcpio.conf

# ── switching to Windows (Limine one-shot) ──────────────────────────────
host /usr/local/bin/reboot-to-windows 755
host /etc/sudoers.d/50-reboot-to-windows 440
