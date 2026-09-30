{ pkgs, ... }:
let
  customPkgs = {
    inherit (pkgs.callPackage ./mutectl { }) mutectl discord;
    spotify-vol = pkgs.callPackage ./spotify-vol { };
    backdrop = pkgs.callPackage ./backdrop { };
  };
in
{
  imports = [
    ./mutectl/service.nix
    ./spotify-vol/service.nix
    ./backdrop/service.nix
  ];
  config = {
    nixpkgs.overlays = [ (final: prev: { _custom = customPkgs; }) ];
  };
}
