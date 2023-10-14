{ pkgs, ... }:
{
    users.users.nico = {
        shell = pkgs.zsh;
        isNormalUser = true;
        description = "nico";
        extraGroups = [ "networkmanager" "wheel" ];
    };
}
