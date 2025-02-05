# Print this help message
default:
    @just --list --unsorted

# nixos-rebuild dry-build
dry:
  nixos-rebuild dry-build --flake .

# build system and print diff with current-system
check:
  nixos-rebuild build --flake .
  nix store diff-closures /run/current-system ./result
  rm result

# build and apply temporarily
test:
  nixos-rebuild test --flake . --use-remote-sudo

# build and switch now
deploy:
  nixos-rebuild switch --flake . --use-remote-sudo

# build and switch on boot
deploy-boot:
  nixos-rebuild boot --flake . --use-remote-sudo

# update flake
up:
  nix flake update

# print history
history:
  nix profile history --profile /nix/var/nix/profiles/system

# just is a command runner, Justfile is very similar to Makefile, but simpler.

############################################################################
#
#  Nix commands related to the local machine
#
############################################################################


# deploy:
#   nixos-rebuild switch --flake . --use-remote-sudo

# debug:
#   nixos-rebuild switch --flake . --use-remote-sudo --show-trace --verbose

# up:
#   nix flake update

# # Update specific input
# # usage: make upp i=home-manager
# upp:
#   nix flake update $(i)

# history:
#   nix profile history --profile /nix/var/nix/profiles/system

# repl:
#   nix repl -f flake:nixpkgs

# clean:
#   # remove all generations older than 7 days
#   sudo nix profile wipe-history --profile /nix/var/nix/profiles/system  --older-than 7d

# gc:
#   # garbage collect all unused nix store entries
#   sudo nix-collect-garbage --delete-old
