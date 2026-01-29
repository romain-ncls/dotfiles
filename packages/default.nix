{ pkgs, ... }:
let
  customPkgs = {
    inherit (pkgs.callPackage ./mutectl { }) mutectl discord;
    mysql-shell-docker = pkgs.callPackage ./mysql-shell-docker { };
  };
in
{
  imports = [ ./mutectl/service.nix ];
  config = {
    nixpkgs.overlays = [ (final: prev: { _custom = customPkgs; }) ];
  };
}
