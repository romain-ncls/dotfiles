{ pkgs, ... }:
let
  customPkgs = {
    inherit (pkgs.callPackage ./mutectl { }) mutectl discord;
    spotify-vol = pkgs.callPackage ./spotify-vol { };
  };
in
{
  imports = [
    ./mutectl/service.nix
    ./spotify-vol/service.nix
  ];
  config = {
    nixpkgs.overlays = [ (final: prev: { _custom = customPkgs; }) ];
  };
}
