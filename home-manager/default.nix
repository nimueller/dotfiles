{ config, pkgs, lib, username, ... }:
{
    # Basic home manager settings
    programs.home-manager.enable = true;

    home.username = username;
    home.homeDirectory = "/home/${username}";
    home.stateVersion = "23.05";

    home.packages = with pkgs; [
        # Terminal programs
        btop
        bat
        lsd
    ];

    programs.zsh = {
        enable = true;
        shellAliases = {
            "cat" = "bat";
            "ls" = "lsd";
            "la" = "lsd -lah";
        };
    };
}
