#!/usr/bin/env bash
# The TV's display settings, through kscreen-doctor. KWin keeps the rest
# (the mode: 4K 120 Hz) in its own kwinoutputconfig.json.
# - every output: 200% scale (a 4K TV);
# - the LG C6 (its EDID: manufacturer GSM, product 33997): HDR with our
#   colour profile (hdr-icc/, home/.local/share/icc/), SDR colour intensity
#   50%, VRR for fullscreen windows only (docs/decisions.md, "OLED TV").
#   With the profile, SDR white (300 nits) and the peak (1950) come from it;
#   System Settings' SDR brightness and peak override no longer apply (the
#   SDR brightness is set to 300 too, for when the profile is off).
set -euo pipefail
command -v kscreen-doctor >/dev/null && [[ -n ${WAYLAND_DISPLAY:-} ]] || exit 0
# The name carries the values: KWin reads a profile again only when its path
# changes, so a new profile needs a new name.
icc=$HOME/.local/share/icc/lg-c6-sdr300-peak1950.icc
for out in $(kscreen-doctor -o | sed 's/\x1b\[[0-9;]*m//g' | awk '$1 == "Output:" { print $3 }'); do
	args=("output.$out.scale.2")
	edid=$(echo /sys/class/drm/card*-"$out"/edid)
	# EDID bytes 8-11: the manufacturer (1e6d: GSM) and product code (cd84: 33997)
	if [[ -r $edid ]] && [[ $(od -An -tx1 -j8 -N4 "$edid" | tr -d ' \n') == 1e6dcd84 ]]; then
		args+=("output.$out.hdr.enable" "output.$out.wcg.enable"
			"output.$out.hdrIccProfile.$icc" "output.$out.hdrColorProfileSource.ICC"
			"output.$out.sdrGamut.50" "output.$out.sdr-brightness.300"
			"output.$out.vrrpolicy.automatic")
	fi
	kscreen-doctor "${args[@]}"
done
