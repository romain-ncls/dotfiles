# KDE Plasma desktop (Wayland) and desktop apps: identical on every machine.

AddPackage plasma-meta
AddPackage plasma-login-manager
AddPackage konsole
AddPackage dolphin
AddPackage ark
AddPackage gwenview
AddPackage kate
AddPackage okular
AddPackage kdialog                         # dialogs for scripts (reboot-to-windows)
AddPackage kde-gtk-config
AddPackage breeze-gtk

# audio
AddPackage pipewire
AddPackage pipewire-alsa
AddPackage pipewire-pulse
AddPackage pipewire-jack
AddPackage wireplumber

# bluetooth (KDE's bluedevil talks to bluetoothd)
AddPackage bluez
AddPackage bluez-utils                     # bluetoothctl
AddPackage --foreign logi-wheel             # pkg/logi-wheel: per-app SmartShift/scroll force (local, not AUR)

# fonts
AddPackage noto-fonts
AddPackage noto-fonts-cjk
AddPackage noto-fonts-emoji
AddPackage ttf-jetbrains-mono
AddPackage ttf-lato                        # Readest's reading font
AddPackage --foreign ttf-literata           # Readest serif (Literata, OFL)
AddPackage --foreign ttf-ms-fonts           # Arial, Trebuchet MS: mpv subtitle presets

# video (mpv's config is mpv/ in this repo, shared with Windows)
AddPackage mpv
AddPackage qbittorrent

# reading (settings: home/.readest, see scripts/readest-config)
AddPackage readest

# browsers
AddPackage firefox
AddPackage --foreign brave-bin

# services
CreateLink /etc/systemd/system/display-manager.service /usr/lib/systemd/system/plasmalogin.service
CreateLink /etc/systemd/system/bluetooth.target.wants/bluetooth.service /usr/lib/systemd/system/bluetooth.service
CreateLink /etc/systemd/system/dbus-org.bluez.service /usr/lib/systemd/system/bluetooth.service
