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

# ── pacman, sudo, shells ────────────────────────────────────────────────
CopyFile /etc/pacman.conf                  # [multilib] enabled
CopyFile /etc/sudoers                      # %wheel ALL=(ALL:ALL) ALL
CopyFile /etc/shells

# ── boot ────────────────────────────────────────────────────────────────
CopyFile /etc/default/limine
CopyFile /etc/mkinitcpio.d/linux.preset

# ── snapper ─────────────────────────────────────────────────────────────
CopyFile /etc/conf.d/snapper
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

# systemd defaults that aconfmgr sees as plain links
CreateLink /etc/systemd/system/autovt@.service /usr/lib/systemd/system/getty@.service
CreateLink /etc/systemd/system/getty.target.wants/getty@tty1.service /usr/lib/systemd/system/getty@.service
CreateLink /etc/systemd/system/multi-user.target.wants/remote-fs.target /usr/lib/systemd/system/remote-fs.target
CreateLink /etc/systemd/system/sockets.target.wants/systemd-userdbd.socket /usr/lib/systemd/system/systemd-userdbd.socket
CreateLink /etc/systemd/user/sockets.target.wants/p11-kit-server.socket /usr/lib/systemd/user/p11-kit-server.socket

# ── file properties that differ from the packages' ──────────────────────
SetFileProperty / mode 555
SetFileProperty /usr/lib/utempter/utempter group utmp
SetFileProperty /usr/lib/utempter/utempter mode 2755
