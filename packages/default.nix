{ config, pkgs, lib, ... }:
let
  customPkgs = {
    mutectl = pkgs.callPackage ./mutectl {};
  };

  cfg = config.services.mutectl;
in {
  options = {
    services.mutectl = {
      enable = lib.mkEnableOption "Enable the mutectl service";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs._custom.mutectl;  # Ensure the package is overridden correctly
        description = "The mutectl package to install";
      };
    };
  };

  config = lib.mkMerge [
    {
      nixpkgs.overlays = [ (final: prev: { _custom = customPkgs; }) ];
    }

    (lib.mkIf cfg.enable {
    # Install the package system-wide
    environment.systemPackages = [ cfg.package ];

    # Define the systemd service
    systemd.services.mutectl = {
      description = "Mute control service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/mutectl-service";
        Restart = "always";
        User = "root";
      };
    };
  })
  ];
}
