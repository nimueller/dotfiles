{ config, pkgs, lib, username, ... }:
{
    # Basic home manager settings
    programs.home-manager.enable = true;

    home.username = username;
    home.homeDirectory = "/home/${username}";
    home.stateVersion = "23.05";

    home.packages = with pkgs; [
        # Terminal programs
        fzf # Lifesaver!
        autojump # Lifesaver #2!
        bat
        lsd
    ];

    imports = [ 
        ./neovim/default.nix
        ./theme/default.nix
    ];

    programs = {
        zsh = {
            enable = true;
            defaultKeymap = null;
            autocd = true;

            # Plugins
            enableAutosuggestions = true;
            enableCompletion = true;
            syntaxHighlighting.enable = true;

            initExtra = builtins.readFile ../config/zshrc;

            oh-my-zsh = {
                enable = true;
                theme = "skaro";
                plugins = [
                    "autojump"
                    "colorize"
                ];
            };

            # Aliases
            shellAliases = {
                "cat" = "bat";
                "ls" = "lsd";
                "la" = "lsd -lah";
                "virsh" = "virsh -c qemu:///system";
                "fzf" = "fzf --reverse";
            };
        };

        btop = {
            enable = true;
            settings = {
                vim_keys = true;
            };
        };
    };
    
}
