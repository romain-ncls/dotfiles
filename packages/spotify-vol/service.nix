{ config, lib, pkgs, ... }:
let cfg = config.services.spotify-vol;
in {
  options = {
    services.spotify-vol = {
      enable = lib.mkEnableOption "Spotify volume control via Super+Shift+Scroll";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs._custom.spotify-vol; # Ensure the package is overridden correctly
        description = "The spotify-vol package to install";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "romain";
        description = "User added to the `input` group so the daemon can read /dev/input.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # The daemon reads /dev/input/event* (root:input 0660) to catch the wheel
    # and the Super/Shift state. Membership takes effect after the next login.
    users.users.${cfg.user}.extraGroups = [ "input" ];

    # Runs in the user session so it can reach the session bus (MPRIS + KDE OSD)
    # and inherit the `input` group.
    systemd.user.services.spotify-vol = {
      description = "Spotify volume control via Super+Shift+Scroll";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/spotify-vol-daemon";
        Restart = "on-failure";
        RestartSec = 3;
      };
    };
  };
}
