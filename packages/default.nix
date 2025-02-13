{ pkgs, lib, ... }:
let
  customPkgs = {
    mutectl = pkgs.callPackage ./mutectl {};
  };
in {
  config = {
    nixpkgs.overlays = [ (final: prev: { _custom = customPkgs; }) ];
  };
}
