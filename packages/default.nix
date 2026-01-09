{ pkgs, ... }:
let
  customPkgs = {
    mutectl = pkgs.callPackage ./mutectl { };
    mysql-shell-docker = pkgs.callPackage ./mysql-shell-docker { };
  };
in
{
  imports = [ ./mutectl/service.nix ];
  config = {
    nixpkgs.overlays = [ (final: prev: { _custom = customPkgs; }) ];
  };
}
