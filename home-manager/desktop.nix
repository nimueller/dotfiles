{ config, pkgs, lib, ... }:
{
    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
        "idea-ultimate"
	    "spotify"
    ];

    fonts.fontconfig.enable = true;

    home.packages = with pkgs; [
        (nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
        jetbrains.idea-ultimate
        spotify
        wl-clipboard
    ];
}
