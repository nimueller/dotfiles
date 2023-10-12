{ config, pkgs, lib, ... }:
{
    programs.home-manager.enable = true;

    home.username = "nico";
    home.homeDirectory = "/home/nico";
    home.stateVersion = "23.05";

    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
        "idea-ultimate"
	    "spotify"
    ];

    home.packages = with pkgs; [
        spotify
        gnome.nautilus
        jetbrains.idea-ultimate
    ];
}