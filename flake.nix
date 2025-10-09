{
  description = "A simple NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-7df7ff.url = "github:NixOS/nixpkgs/7df7ff7d8e00218376575f0acdcc5d66741351ee"; # for jetbrains IDEs
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-7df7ff,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs-7df7ff = import nixpkgs-7df7ff {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;

        specialArgs = { inherit inputs pkgs-7df7ff; };

        modules = [
          ./packages
          ./hosts/nixos/default.nix
        ];
      };
    };
}
