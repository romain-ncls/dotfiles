#!/usr/bin/env bash
# A self-signed certificate for KRDP, per machine (what System Settings would
# generate). Its paths are the Certificate keys of module.yaml.
set -euo pipefail
dir=$HOME/.local/share/krdpserver
if [[ ! -f $dir/krdp.crt || ! -f $dir/krdp.key ]]; then
	mkdir -p "$dir"
	openssl req -nodes -new -x509 -days 3650 -batch \
		-keyout "$dir/krdp.key" -out "$dir/krdp.crt" 2>/dev/null
fi
