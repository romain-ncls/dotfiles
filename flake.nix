{
  description = "A simple NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    hister.url = "github:asciimoo/hister";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-hardware,
      hister,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;

        specialArgs = { inherit inputs; };

        modules = [
          ./packages
          ./hosts/nixos/default.nix
          nixos-hardware.nixosModules.hp-probook-460G11
          hister.nixosModules.default
        ];
      };
    };
}
