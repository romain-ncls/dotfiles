{
  description = "A simple NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    hister.url = "github:asciimoo/hister?rev=81e401d069b7ed9ced35827db3fe238b11fb39cc";
    awpro.url = "github:romain-ncls/awpro?rev=a061c7105e1357ecb53dbeba949e5977866a0c0b";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-hardware,
      hister,
      awpro,
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
          awpro.nixosModules.default
        ];
      };
    };
}
