{ config, lib, pkgs, ... }:
let
  cfg = config.services.backdrop;
  settingsFormat = pkgs.formats.json { };
in {
  options = {
    services.backdrop = {
      enable = lib.mkEnableOption "Backdrop wallpapers (Spotlight, Bing, Wallhaven) tuned by likes and dislikes";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs._custom.backdrop;
        description = "The backdrop package to install";
      };

      settings = lib.mkOption {
        type = settingsFormat.type;
        default = { };
        example = {
          interval = "2h";
          sources.bing = 0;
          wallhaven.queries = [ "digital art" "cyberpunk" ];
        };
        description = ''
          Overrides of the daemon defaults, see Config in
          packages/backdrop/daemon/config.go.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Also installs the wallpaper plugin; select it once with `backdrop setup`.
    environment.systemPackages = [ cfg.package ];

    systemd.user.services.backdrop = {
      description = "Backdrop wallpaper daemon";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} daemon --config ${settingsFormat.generate "backdrop.json" cfg.settings}";
        Restart = "always";
        RestartSec = 5;
      };
    };
  };
}
