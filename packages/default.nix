{ pkgs, ... }:
let
  customPkgs = {
    inherit (pkgs.callPackage ./mutectl { }) mutectl discord;
  };
in
{
  imports = [ ./mutectl/service.nix ];
  config = {
    nixpkgs.overlays = [ (final: prev: { _custom = customPkgs; }) ];
  };
}
