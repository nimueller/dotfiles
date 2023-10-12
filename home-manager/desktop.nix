{ config, pkgs, lib, ... }:
{
    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
        "idea-ultimate"
	    "spotify"
    ];

    home.packages = with pkgs; [
        jetbrains.idea-ultimate
        spotify
    ];
}