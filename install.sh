#!/usr/bin/env bash
# Installs a host of this repo on a blank disk, from the Arch live USB:
#
#   loadkeys fr
#   iwctl station wlan0 connect "<SSID>"     # or plug in ethernet
#   curl -fsSL https://raw.githubusercontent.com/romain-ncls/dotfiles/main/install.sh | bash -s -- <host>
#
# Options before the host: --branch <name> (default main), --repo-url <url>.
# --yes and --disk </dev/…> are passed to lodestar install (tests).
#
# It builds lodestar from the repo, then runs `lodestar install <host>`.
# Everything is one function called on the last line, so a download cut
# halfway runs nothing.
main() {
	set -euo pipefail
	local branch=main url=https://github.com/romain-ncls/dotfiles.git host=""
	local extra=()
	while [[ $# -gt 0 ]]; do
		case $1 in
		--branch) branch=$2; shift 2 ;;
		--repo-url) url=$2; shift 2 ;;
		--yes) extra+=(--yes); shift ;;
		--disk) extra+=(--disk "$2"); shift 2 ;;
		-*) echo "install.sh: unknown option $1" >&2; exit 2 ;;
		*) host=$1; shift ;;
		esac
	done
	if [[ -z $host ]]; then
		echo "usage: install.sh [--branch <name>] [--repo-url <url>] <host>" >&2
		exit 2
	fi
	if [[ $EUID -ne 0 || ! -d /run/archiso ]]; then
		echo "install.sh: run it as root on the Arch live USB" >&2
		exit 1
	fi

	echo "==> More room on the live USB (its RAM disk is 256 MiB; git and Go need about 300)"
	mount -o remount,size=2G /run/archiso/cowspace

	echo "==> git and Go"
	pacman -Sy --noconfirm --needed archlinux-keyring git go

	echo "==> The repo ($branch)"
	rm -rf /root/dotfiles
	git clone --branch "$branch" "$url" /root/dotfiles

	echo "==> Building lodestar"
	(cd /root/dotfiles/lodestar && CGO_ENABLED=0 go build -o /root/lodestar .)

	# Piped into bash, the script's input is the download: lodestar and
	# cryptsetup must read the terminal instead.
	exec /root/lodestar install "$host" --repo /root/dotfiles "${extra[@]}" </dev/tty
}

main "$@"
