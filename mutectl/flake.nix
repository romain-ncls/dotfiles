{
  description = "MuteCtl";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux"; # Change this if needed
      pkgs = import nixpkgs { inherit system; };
    in {
      packages.${system}.default = pkgs.stdenv.mkDerivation {
        pname = "mutectl";
        version = "0.0.1";

        buildInputs = [ pkgs.deno ];

        src = ./.;

        installPhase = ''
          mkdir -p $out/bin
          cp mutectl $out/bin/
          cp mutectl-service.ts $out/bin/mutectl-service
          chmod +x $out/bin/*
        '';

        meta = {
          description = "MuteCtl: control system mute state from devices to clients like discord";
          license = pkgs.lib.licenses.mit;
          maintainers = [ "romain-ncls" ];
        };
      };

      defaultPackage.${system} = self.packages.${system}.default;
      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/mutectl-service";
      };

      # Systemd service for NixOS
      nixosModules.default = { config, lib, pkgs, ... }: {
        systemd.services.mutectl = {
          description = "MuteCtl";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = "${self.packages.${system}.default}/bin/mutectl-service";
            Restart = "always";
            User = "nobody";
            Group = "nogroup";
            StandardOutput = "journal";
            StandardError = "journal";
          };
        };
      };
    };
}
