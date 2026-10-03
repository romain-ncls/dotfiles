# Base system: identical on every machine.

# ── packages ────────────────────────────────────────────────────────────
AddPackage base
AddPackage base-devel
AddPackage linux
AddPackage linux-headers
AddPackage linux-firmware
AddPackage intel-ucode                     # both machines are Intel
AddPackage sof-firmware
AddPackage btrfs-progs
AddPackage dosfstools
AddPackage efibootmgr
AddPackage sudo
AddPackage man-db
AddPackage man-pages
AddPackage vim
AddPackage fish
AddPackage git
AddPackage openssh
AddPackage networkmanager
AddPackage iwd
AddPackage pacman-contrib                  # paccache
AddPackage reflector

# boot: Limine, entries generated from /etc/default/limine + /etc/kernel/cmdline
AddPackage limine
AddPackage --foreign limine-mkinitcpio-hook
AddPackage --foreign limine-snapper-sync

# snapshots
AddPackage snapper
AddPackage snap-pac
AddPackage inotify-tools                   # limine-snapper-sync's watcher

# AUR helper and this repo's own tooling
AddPackage --foreign yay
AddPackage --foreign aconfmgr-git

# ── locale, keyboard, time ──────────────────────────────────────────────
CopyFile /etc/locale.conf                  # English UI, French date/time formats
CopyFile /etc/locale.gen
CopyFile /etc/vconsole.conf                # KEYMAP=fr
CopyFile /etc/X11/xorg.conf.d/00-keyboard.conf   # fr for the login screen and Plasma
CreateLink /etc/localtime /usr/share/zoneinfo/Europe/Paris

# ── pacman, sudo ────────────────────────────────────────────────
CopyFile /etc/pacman.conf                  # [multilib] enabled
CopyFile /etc/sudoers                      # %wheel ALL=(ALL:ALL) ALL

# ── boot ────────────────────────────────────────────────────────────────
CopyFile /etc/default/limine

# ── snapper ─────────────────────────────────────────────────────────────
CopyFile /etc/snapper/configs/root 640

# ── services ────────────────────────────────────────────────────────────
CreateLink /etc/systemd/system/multi-user.target.wants/NetworkManager.service /usr/lib/systemd/system/NetworkManager.service
CreateLink /etc/systemd/system/dbus-org.freedesktop.nm-dispatcher.service /usr/lib/systemd/system/NetworkManager-dispatcher.service
CreateLink /etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service /usr/lib/systemd/system/NetworkManager-wait-online.service
CreateLink /etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service /usr/lib/systemd/system/systemd-timesyncd.service
CreateLink /etc/systemd/system/dbus-org.freedesktop.timesync1.service /usr/lib/systemd/system/systemd-timesyncd.service
CreateLink /etc/systemd/system/multi-user.target.wants/limine-snapper-sync.service /usr/lib/systemd/system/limine-snapper-sync.service
CreateLink /etc/systemd/system/limine-snapper-watcher.service /usr/lib/systemd/system/limine-snapper-sync.service
CreateLink /etc/systemd/system/timers.target.wants/snapper-cleanup.timer /usr/lib/systemd/system/snapper-cleanup.timer
CreateLink /etc/systemd/system/timers.target.wants/snapper-timeline.timer /usr/lib/systemd/system/snapper-timeline.timer
CreateLink /etc/systemd/system/timers.target.wants/paccache.timer /usr/lib/systemd/system/paccache.timer
CreateLink /etc/systemd/system/timers.target.wants/reflector.timer /usr/lib/systemd/system/reflector.timer
