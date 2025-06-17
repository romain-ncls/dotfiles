{ pkgs, ... }:
let
  muteCtlPlugin = ../../packages/mutectl/mutectl-vencord-plugin.ts;
  discord-modded = (
    pkgs.discord.override {
      withOpenASAR = true;
      withVencord = true;
      vencord = (
        pkgs.vencord.overrideAttrs (
          finalAttrs: previousAttrs: {
            preBuild = ''
              mkdir src/userplugins
              cp ${muteCtlPlugin} src/userplugins/mutectl.ts
            '';
          }
        )
      );
    }
  );
in
{
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji
    noto-fonts-monochrome-emoji
    (fira-code.override {
      useVariableFont = false;
    })
    fira-code-symbols
  ];

  environment.systemPackages = with pkgs; [
    libva-utils
    libnotify # For `notify-send`
    alsa-utils # needed for `amixer` for mutectl
    # at # echo 'notify-send -u critical "Reminder" "GitLab Update"' | at 15:15
    vim
    wget
    curl
    neofetch
    bat
    eza
    doggo
    ripgrep
    fzf
    htop
    bottom
    zip
    unzip
    nmap
    ncdu
    bemenu # Menu picker for soundbox `~/scripts/soundbox`
    bemoji # Bemenu emoji picker.
    wl-clipboard # Wayland copy/paste support for bemenu
    wtype # Wayland typing support for bemenu. # doesn't work
    bc # Calculator used by `~/scripts/mutectl`
    caligula # ISO burner TUI
    ffmpeg # Used for conversion to mono in the soundbox
    xdotool # Used for the "focus discord" shortcut

    konsave # KDE settings exporter.

    git
    gh # github CLI
    nixfmt-rfc-style # nix formatter
    nil # nix language server
    jq
    just
    tokei
    deno
    nodePackages_latest.nodejs
    pnpm
    go
    gcc # Needed for `go test -race`
    graphviz # used by pprof
    jdk # Java LTS

    gparted
    vlc
    brave
    vscode
    jetbrains.goland
    steam-run # use to start remote code with me
    gitkraken
    postman
    discord-modded
    flameshot
    spotify
    helvum # PipeWire Patchbay
    easyeffects # Audio effects for PipeWire applications
    rquickshare
  ];

  services.mutectl.enable = true;

  programs.firefox.enable = true;

  programs.fish.enable = true;

  services.flatpak.enable = true;

  virtualisation.docker.enable = true;

  #############################################################################
  ############################ SSH passphrase setup ###########################
  #############################################################################

  # services.gnome.gnome-keyring.enable = true;
  # programs.ssh.startAgent = true;
  # security.pam.services.sddm.enableGnomeKeyring = true;

  programs = {
    ssh.startAgent = true;
    ssh.askPassword = pkgs.lib.mkForce "${pkgs.kdePackages.ksshaskpass.out}/bin/ksshaskpass";
  };

  systemd.user.services.add_ssh_keys = {
    script = ''
      ssh-add $HOME/.ssh/id_ed25519
    '';
    wantedBy = [ "multi-user.target" ]; # starts after login
  };

  environment.sessionVariables = {
    SSH_ASKPASS_REQUIRE = "prefer";
  };

  #############################################################################
  ################################### nix-ld ##################################
  #############################################################################

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = [
    # Add any missing dynamic libraries for unpackaged programs
    # here, NOT in environment.systemPackages

    ############### goland ###############
    # enabled for full line completion
    # no library needed for now
  ];
}
