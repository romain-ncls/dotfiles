{ pkgs, ... }:
pkgs.stdenv.mkDerivation {
  pname = "mysql-shell-docker";
  version = "8.4.0";

  buildInputs = [ ];

  src = ./.;

  installPhase = ''
    mkdir -p $out/bin
    cp mysqlsh $out/bin/
    chmod +x $out/bin/*
  '';

  meta = {
    description = "mysql-shell packaged in a Docker container";
    license = pkgs.lib.licenses.mit;
    maintainers = [ "romain-ncls" ];
  };
}
