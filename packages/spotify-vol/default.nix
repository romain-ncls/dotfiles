{
  lib,
  buildGoModule,
}:
buildGoModule {
  pname = "spotify-vol";
  version = "0.1.0";

  src = ./daemon;
  vendorHash = "sha256-WUTGAYigUjuZLHO1YpVhFSWpvULDZfGMfOXZQqVYAfs=";

  meta = {
    description = "Control Spotify volume over MPRIS DBus, with a Super+Shift+Scroll daemon";
    license = lib.licenses.mit;
    maintainers = [ "romain-ncls" ];
    mainProgram = "spotify-vol";
    platforms = lib.platforms.linux;
  };
}
