{ pkgs, ... }:
{
  mutectl = pkgs.stdenv.mkDerivation {
    pname = "mutectl";
    version = "0.0.3";

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

  discord = pkgs.discord.override {
    withOpenASAR = true;
    withVencord = true;
    vencord = (
      pkgs.vencord.overrideAttrs (
        finalAttrs: previousAttrs:
        let
          muteCtlPlugin = ./mutectl-vencord-plugin.ts;
        in
        {
          preBuild = ''
            mkdir src/userplugins
            cp ${muteCtlPlugin} src/userplugins/mutectl.ts
          '';
        }
      )
    );
  };
}
