{
  lib,
  stdenv,
  makeWrapper,
  bash,
  curl,
  gawk,
  pipewire,
  qt6,
  buildGoModule,
  discord,
  openasar,
  vencord,
}:
let
  mutectl-service = buildGoModule {
    pname = "mutectl-service";
    version = "0.1.0";

    src = ./mutectl-service;
    vendorHash = null;

    meta.mainProgram = "mutectl-service";
  };
in
{
  mutectl = stdenv.mkDerivation {
    pname = "mutectl";
    version = "0.1.0";

    nativeBuildInputs = [
      makeWrapper
    ];

    src = ./.;

    installPhase = ''
      mkdir -p $out/bin

      install -m +x mutectl $out/bin/mutectl
      wrapProgram $out/bin/mutectl --prefix PATH : ${
        lib.makeBinPath [
          curl
          gawk
          pipewire
          qt6.qttools
        ]
      }

      ln -s ${lib.getExe mutectl-service} $out/bin/mutectl-service
    '';

    meta = {
      description = "MuteCtl: control system mute state from devices to clients like discord";
      license = lib.licenses.mit;
      maintainers = [ "romain-ncls" ];
    };
  };

  discord = discord.override {
    withOpenASAR = true;
    withVencord = true;
    # OpenAsar's default "perf" preset force-enables Chromium's DrDc feature, which is
    # off by default on desktop Linux. On this Meteor Lake iGPU, DrDc combined with
    # VA-API H.264 decode aborts the GPU process (SIGTRAP) every few minutes, which
    # DrKonqi then reports as a Discord crash. Drop just that one flag; the rest of
    # the preset (GPU rasterization, zero-copy, hardware overlays) is kept.
    openasar = openasar.overrideAttrs (previousAttrs: {
      postPatch = (previousAttrs.postPatch or "") + ''
        substituteInPlace src/cmdSwitches.js \
          --replace-fail '--enable-features=EnableDrDc,' '--enable-features='
      '';
    });
    vencord = (
      vencord.overrideAttrs (
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
