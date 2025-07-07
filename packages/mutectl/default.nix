{ pkgs, ... }:
pkgs.stdenv.mkDerivation {
  pname = "mutectl";
  version = "0.0.2";

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
}
