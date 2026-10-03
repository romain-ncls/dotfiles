# Work PC only: Intel Core Ultra 5 125U (Meteor Lake), integrated graphics,
# LUKS, no dual-boot. Not installed yet: fill in from the first `aconfmgr save`
# on that machine. Host-specific files go under files/hosts/work/.
[[ $HOSTNAME != menadion ]] || return 0

host() { CopyFileTo "/hosts/work$1" "$1" "${@:2}"; }

# Intel graphics and video decode (Arc iGPU)
AddPackage mesa
AddPackage vulkan-intel
AddPackage intel-media-driver

# TODO once installed: hostname, hosts, fstab, kernel/cmdline (rd.luks… / root=),
# mkinitcpio.conf with sd-encrypt — as `host /etc/…` lines like 50-home.sh.
