{ pkgs, ... }:
{
    users.users.nico = {
        isNormalUser = true;
        description = "nico";
        extraGroups = [ "networkmanager" "wheel" ];
    };
}
