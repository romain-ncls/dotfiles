{
  lib,
  stdenv,
  makeWrapper,
  bash,
  curl,
  gawk,
  pipewire,
  qt6,
  deno,
  discord,
  openasar,
  vencord,
}:
{
  mutectl = stdenv.mkDerivation {
    pname = "mutectl";
    version = "0.0.5";

    buildInputs = [
      deno
    ];
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

      mkdir -p $out/lib/mutectl
      cp mutectl-service.ts $out/lib/mutectl/

      cat > $out/bin/mutectl-service <<EOF
      #!/bin/sh
      exec ${deno}/bin/deno -q run --allow-net $out/lib/mutectl/mutectl-service.ts "\$@"
      EOF

      chmod +x $out/bin/mutectl-service
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
