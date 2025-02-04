{ pkgs, ... }:
{
  users.users.romain = {
    isNormalUser = true;
    description = "Romain";
    shell = pkgs.fish;
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    # packages = with pkgs; [
    # ];
  };
}
