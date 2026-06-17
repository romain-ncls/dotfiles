{
  lib,
  stdenv,
  makeWrapper,
  buildGoModule,
  bash,
  glib,
  gawk,
  gnugrep,
  coreutils,
}:
let
  daemon = buildGoModule {
    pname = "spotify-vol-daemon";
    version = "0.1.0";
    src = ./daemon;
    vendorHash = null; # no external dependencies
  };
in
stdenv.mkDerivation {
  pname = "spotify-vol";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin

    # CLI: spotify-vol {up|down|set <0-100>|get}
    install -m755 spotify-vol $out/bin/spotify-vol
    wrapProgram $out/bin/spotify-vol \
      --prefix PATH : ${
        lib.makeBinPath [
          bash # `#!/usr/bin/env bash` shebang under the minimal systemd env
          glib # gdbus
          gawk
          gnugrep
          coreutils
        ]
      }

    # Daemon: Super+Shift+Scroll -> spotify-vol up/down
    makeWrapper ${daemon}/bin/spotify-vol-daemon $out/bin/spotify-vol-daemon \
      --set SPOTIFY_VOL "$out/bin/spotify-vol"
  '';

  meta = {
    description = "Control Spotify volume over MPRIS DBus, with a Super+Shift+Scroll daemon";
    license = lib.licenses.mit;
    maintainers = [ "romain-ncls" ];
    platforms = lib.platforms.linux;
  };
}
