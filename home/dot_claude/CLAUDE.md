# This machine is managed by ~/dotfiles

Every package, system file, service and user config on this machine is declared
in `~/dotfiles` (chezmoi for `$HOME`, aconfmgr for the system). The rule: **no
change lives only on the machine.**

Whenever a task changes configuration — installs or removes a package, edits a
file in `/etc` or `/boot`, enables a service, changes a KDE/app setting, adds a
shell alias, anything another machine would need — also make that change in
`~/dotfiles`, or document it there if it cannot be scripted. Read
`~/dotfiles/CLAUDE.md` first for where things go and how to apply them. This
applies whatever directory the session started in.

If a change was made outside the repo, say so and offer to bring it in.
