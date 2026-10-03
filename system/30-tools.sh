# Command-line tools: identical on every machine.

AddPackage chezmoi                         # $HOME side of this repo
AddPackage just                            # this repo's task runner
AddPackage bitwarden-cli                   # secrets for chezmoi templates
AddPackage jq                              # Claude Code status line
AddPackage github-cli
AddPackage --foreign claude-code
AddPackage --foreign visual-studio-code-bin    # settings + extensions still on Settings Sync (docs/decisions.md)
