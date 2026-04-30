{ pkgs, ... }:
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
    usbutils
    pciutils
    libva-utils
    libnotify # For `notify-send`
    vim
    wget
    curl
    fastfetch
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
    bemenu # dmenu for the soundboard
    bemoji # Bemenu emoji picker.
    tofi # Alternative dmenu for the soundboard
    wl-clipboard # Wayland copy/paste support for bemenu
    wtype # Wayland typing support for bemenu. # doesn't work
    caligula # ISO burner TUI
    ffmpeg # Used for conversion to mono in the soundbox
    xdotool # Used for the "focus discord" shortcut
    mkpasswd # To hash bcrypt passwords
    openssl

    kdePackages.qtwebengine # needed by HTML wallpaper
    konsave # KDE settings exporter.
    kdePackages.kdeconnect-kde
    (pkgs.kdePackages.spectacle.override {
      # Add OCR support to spectacle
      tesseractLanguages = [
        "eng"
        "fra"
      ];
    })

    git
    gh # github CLI
    nixfmt # nix formatter
    nil # nix language server
    jq
    yq-go
    just
    tokei
    deno
    nodejs_latest
    pnpm
    go
    gcc # Needed for `go test -race`
    graphviz # used by pprof
    jdk # Java LTS
    uv # Python dependency manager
    kind # Kubernetes in Docker
    kubectl
    yamllint # YAML linter use by Infra repo git hooks
    mysql-shell
    bitwarden-cli
    bws # Bitwarden Secret Manager CLI
    s5cmd # s3 client
    age # backup encryption
    claude-code

    bitwarden-desktop
    gparted
    vlc
    brave
    vscode
    jetbrains.goland
    jetbrains.webstorm
    jetbrains.pycharm
    jetbrains.datagrip
    steam-run # use to start remote code with me
    gitkraken
    postman
    _custom.discord
    # flameshot
    spotify
    crosspipe # PipeWire graph
    easyeffects # Audio effects for PipeWire applications
    packet # QuickShare client
    readest
    obsidian
  ];

  services.mutectl.enable = true;

  programs.firefox.enable = true;

  programs.fish.enable = true;

  services.flatpak.enable = true;

  virtualisation.docker.enable = true;

  services.atd.enable = true; # echo 'notify-send -u critical "Reminder" "GitLab Update"' | at 15:15

  programs.droidcam.enable = true;

  programs.steam.enable = true;

  systemd.user.services.easyeffects = {
    enable = true;
    description = "Easyeffects daemon";

    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    requires = [ "dbus.service" ];
    partOf = [
      "graphical-session.target"
      "pipewire.service"
    ];

    serviceConfig = {
      ExecStart = "${pkgs.easyeffects}/bin/easyeffects --gapplication-service";
      ExecStop = "${pkgs.easyeffects}/bin/easyeffects --quit";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  services.hister = {
    enable = true;
    config = {
      server = {
        address = "127.0.0.1:44333";
      };
    };
  };

  programs.awpro.enable = true;

  #############################################################################
  ############################ SSH passphrase setup ###########################
  #############################################################################

  # services.gnome.gnome-keyring.enable = true;
  # programs.ssh.startAgent = true;
  # security.pam.services.sddm.enableGnomeKeyring = true;

  # programs = {
  #   ssh.startAgent = true;
  #   # ssh.askPassword = pkgs.lib.mkForce "${pkgs.kdePackages.ksshaskpass.out}/bin/ksshaskpass";
  #   # ssh.askPassword = pkgs.lib.mkForce "${pkgs.x11_ssh_askpass}/libexec/x11-ssh-askpass";
  # };

  # systemd.user.services.add_ssh_keys = {
  #   script = ''
  #     ssh-add $HOME/.ssh/id_ed25519
  #   '';
  #   wantedBy = [ "multi-user.target" ]; # starts after login
  # };

  # environment.sessionVariables = {
  #   SSH_ASKPASS_REQUIRE = "prefer";
  # };
  # services.gnome.gnome-keyring.enable = true;
  # security.pam.services.sddm.enableGnomeKeyring = true;
  # programs.ssh.startAgent = true;

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
