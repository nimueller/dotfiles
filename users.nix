{ pkgs, ... }:
{
    users.users.nico = {
        isNormalUser = true;
        description = "nico";
        extraGroups = [ "networkmanager" "wheel" ];
    };

    home-manager.users.nico = { lib, pkgs, ... }: {
        nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
            "idea-ultimate"
	    "spotify"
        ];

        home = {
            packages = with pkgs; [
	    	spotify
                gnome.nautilus
                jetbrains.idea-ultimate
            ];
            stateVersion = "23.05";
        };
    };
}
