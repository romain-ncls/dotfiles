{
  description = "A simple NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    hister.url = "github:asciimoo/hister?rev=81e401d069b7ed9ced35827db3fe238b11fb39cc";
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
