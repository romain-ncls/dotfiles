#!/usr/bin/env bash
# Applies test/container/repo to a throwaway Arch container and checks the
# result: packages, files, modes, checks, links, units, the user, home files,
# then removals. Needs Docker and network access.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
(cd "$here/.." && CGO_ENABLED=0 go build -o "$tmp/lodestar" .)
docker run --rm --memory 2g \
	-v "$tmp/lodestar:/usr/local/bin/lodestar:ro" \
	-v "$here/container/repo:/repo-src:ro" \
	-v "$here/container/inside.sh:/inside.sh:ro" \
	archlinux:latest bash /inside.sh
