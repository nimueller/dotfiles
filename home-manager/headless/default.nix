{ pkgs, username, config, ... }:
{
  # Basic home manager settings
  programs.home-manager.enable = true;
  services.home-manager.autoExpire = {
    enable = true;
    frequency = "weekly";
    store = {
      cleanup = true;
      options = "--delete-older-than 7d";
    };
    timestamp = "-7 days";
  };

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "23.05";

  home.packages = with pkgs; [
    # Terminal programs
    tmux # GOAT
    fzf # Lifesaver!
    autojump # Lifesaver #2!
    tldr
    bat
    lsd
    jq
    lua
    tree
  ];

  imports = [
    ./neovim.nix
    ./symlinks.nix
    ../theme/default.nix
  ];

  home.file.".p10k.zsh".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/zsh/p10k.zsh";

  programs = {
    zsh = {
      enable = true;
      autosuggestion = {
        enable = true;
      };
      syntaxHighlighting = {
        enable = true;
      };
      oh-my-zsh = {
        enable = true;
        plugins = [
          "colored-man-pages"
          "command-not-found"
          "docker"
          "fzf"
          "git"
          "sudo"
          "tmux"
          "autojump"
          "colorize"
        ];
      };
      plugins = [
        {
          name = "powerlevel10k";
          src = pkgs.zsh-powerlevel10k;
          file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
        }
      ];
      initContent = builtins.readFile ../../config/zsh/init-content.zsh;
    };

    btop = {
      enable = true;
      settings = {
        vim_keys = true;
      };
    };

    git = {
      enable = true;
      lfs.enable = true;
      signing = {
        signByDefault = true;
        key = "~/.ssh/id_rsa_github.pub";
        format = "ssh";
      };
      settings = {
        user = {
          name = "Nico Müller";
          email = "mueller@cryptospace.dev";
        };

        init.defaultBranch = "main";
        difftool.prompt = false;
        diff.tool = "nvimdiff";
        merge.tool = "nvimdiff";

        alias = {
          tree = "log --oneline --graph --all";
        };
      };
    };
  };
}
