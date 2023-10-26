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
        defaultKeymap = null;
        autocd = true;

        # Plugins
        enableAutosuggestions = true;
        enableCompletion = true;
        syntaxHighlighting.enable = true;

        oh-my-zsh = {
            enable = true;
            theme = "skaro";
            plugins = [
                "colorize"
            ];
        };

        # Aliases
        shellAliases = {
            "cat" = "bat";
            "ls" = "lsd";
            "la" = "lsd -lah";
        };
    };
}
