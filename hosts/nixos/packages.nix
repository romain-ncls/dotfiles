{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    libva-utils
    libnotify # For `notify-send`
    # at # echo 'notify-send -u critical "Reminder" "GitLab Update"' | at 15:15
    vim
    wget
    curl
    neofetch
    cmatrix
    bat
    eza
    doggo
    ripgrep
    fzf
    htop
    bottom
    zip
    tree
    nmap
    ncdu
    bemenu # Menu picker for soundbox `~/scripts/soundbox`
    bemoji # Bemenu emoji picker.
    wl-clipboard # Wayland copy/paste support for bemenu
    wtype # Wayland typing support for bemenu. # doesn't work
    bc # Calculator used by `~/scripts/mutectl`
    caligula # ISO burner TUI
    ffmpeg # Used for conversion to mono in the soundbox

    konsave # KDE settings exporter.

    git
    gh
    jq
    just
    tokei
    deno
    nodejs_23
    go
    gcc # Needed for `go test -race`

    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji
    noto-fonts-monochrome-emoji
    fira-code
    fira-code-symbols

    gparted
    vlc
    brave
    vscode
    jetbrains.goland
    gitkraken
    postman
    discord
    flameshot
    spotify
    helvum # PipeWire Patchbay
  ];

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
    ssh.askPassword = pkgs.lib.mkForce "${pkgs.ksshaskpass.out}/bin/ksshaskpass";
  };

  systemd.user.services.add_ssh_keys = {
    script = ''
      ssh-add $HOME/.ssh/id_ed25519
    '';
    wantedBy = [ "multi-user.target" ];  #starts after login
  };

  environment.sessionVariables = {
    SSH_ASKPASS_REQUIRE="prefer";
  };

  #############################################################################
  ################################### nix-ld ##################################
  #############################################################################

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Add any missing dynamic libraries for unpackaged programs
    # here, NOT in environment.systemPackages

    ############### goland ###############
    # enabled for full line completion
    # no library needed for now
  ];
}
