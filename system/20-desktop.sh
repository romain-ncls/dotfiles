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

# fonts
AddPackage noto-fonts
AddPackage noto-fonts-cjk
AddPackage noto-fonts-emoji
AddPackage ttf-jetbrains-mono

# browsers
AddPackage firefox
AddPackage --foreign brave-bin

# services
CreateLink /etc/systemd/system/display-manager.service /usr/lib/systemd/system/plasmalogin.service
