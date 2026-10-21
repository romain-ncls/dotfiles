set -l commands apply check drift kde plan prune schema upgrade
complete -c lodestar -f
complete -c lodestar -n "not __fish_seen_subcommand_from $commands" -a apply -d 'make the machine match the repo'
complete -c lodestar -n "not __fish_seen_subcommand_from $commands" -a check -d "validate a host's config"
complete -c lodestar -n "not __fish_seen_subcommand_from $commands" -a drift -d 'what is on the machine but not in the repo'
complete -c lodestar -n "not __fish_seen_subcommand_from $commands" -a kde -d 'review or watch KDE settings'
complete -c lodestar -n "not __fish_seen_subcommand_from $commands" -a plan -d 'what apply would change'
complete -c lodestar -n "not __fish_seen_subcommand_from $commands" -a prune -d "remove packages the repo doesn't declare"
complete -c lodestar -n "not __fish_seen_subcommand_from $commands" -a schema -d 'regenerate the JSON Schemas'
complete -c lodestar -n "not __fish_seen_subcommand_from $commands" -a upgrade -d 'yay -Syu, rebuild local packages, apply'
complete -c lodestar -n "__fish_seen_subcommand_from kde; and not __fish_seen_subcommand_from review watch" -a review -d 'keep, ignore or undo KDE changes'
complete -c lodestar -n "__fish_seen_subcommand_from kde; and not __fish_seen_subcommand_from review watch" -a watch -d 'the keys one change sets'
complete -c lodestar -l repo -r -F -d 'the dotfiles repo'
complete -c lodestar -l host -x -a '(path basename (path filter -d ~/dotfiles/hosts/*))' -d 'the host to use'
complete -c lodestar -l yes -d 'apply without asking'
complete -c lodestar -l list -d 'kde review: print the changes as YAML'
