{ pkgs, ... }:
let customPkgs = { mutectl = pkgs.callPackage ./mutectl { }; };
in {
  imports = [ ./mutectl/service.nix ];
  config = { nixpkgs.overlays = [ (final: prev: { _custom = customPkgs; }) ]; };
}
