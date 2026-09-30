{
  lib,
  buildGoModule,
}:
buildGoModule {
  pname = "backdrop";
  version = "0.1.0";

  src = ./daemon;
  vendorHash = "sha256-WUTGAYigUjuZLHO1YpVhFSWpvULDZfGMfOXZQqVYAfs=";

  # The Plasma wallpaper plugin, found by plasmashell and the lock screen
  # through the system profile's share/plasma/wallpapers. It runs the CLI by
  # store path rather than relying on plasmashell's PATH.
  postInstall = ''
    plugin=$out/share/plasma/wallpapers/com.github.romain-ncls.backdrop
    mkdir -p $plugin
    cp -r ${./plasma}/. $plugin
    chmod -R u+w $plugin
    substituteInPlace $plugin/contents/ui/Backend.qml --replace-fail '@backdrop@' $out/bin/backdrop
  '';

  meta = {
    description = "Wallpapers from Windows Spotlight, Bing and Wallhaven, picked by likes and dislikes";
    license = lib.licenses.mit;
    maintainers = [ "romain-ncls" ];
    mainProgram = "backdrop";
    platforms = lib.platforms.linux;
  };
}
