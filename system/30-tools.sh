# Command-line tools: identical on every machine.

AddPackage chezmoi                         # $HOME side of this repo
AddPackage just                            # this repo's task runner
AddPackage bitwarden-cli                   # secrets for chezmoi templates
AddPackage jq                              # Claude Code status line
AddPackage github-cli
AddPackage --foreign claude-code
AddPackage --foreign visual-studio-code-bin    # settings + extensions still on Settings Sync (docs/decisions.md)

# Docker: socket-activated, so the daemon only starts when something talks to it.
# /var/lib/docker is its own subvolume (@var_lib_docker), out of snapper's root snapshots.
AddPackage docker
AddPackage docker-compose                  # `docker compose` plugin
AddPackage docker-buildx                   # `docker build` backend
CreateLink /etc/systemd/system/sockets.target.wants/docker.socket /usr/lib/systemd/system/docker.socket
