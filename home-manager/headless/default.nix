{ config, lib, pkgs, username, ... }:
{
  # Basic home manager settings
  programs.home-manager.enable = true;

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "23.05";

  home.packages = with pkgs; [
    # Ensure essential programs are installed
    gcc

    # Terminal programs
    fzf # Lifesaver!
    autojump # Lifesaver #2!
    tldr
    bat
    lsd

    typescript
    sassc
    copilot-cli
  ];

  imports = [
    ./tmux.nix
    ./neovim.nix
    ../theme/default.nix
  ];

  programs = {
    zsh = {
      enable = true;
      defaultKeymap = null;
      autocd = true;

      # Plugins
      autosuggestion.enable = true;
      enableCompletion = true;
      syntaxHighlighting.enable = true;

      initExtra = builtins.readFile ../../config/zshrc;

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

    git = {
      enable = true;
      lfs.enable = true;
      userEmail = "mueller@cryptospace.dev";
      userName = "Nico Müller";
      signing = {
        signByDefault = true;
        key = "~/.ssh/id_rsa_github.pub";
      };
      extraConfig = {
        init.defaultBranch = "main";
        gpg.format = "ssh";
        difftool.prompt = false;
        diff.tool = "nvimdiff";
        merge.tool = "nvimdiff";
      };
      aliases = {
        tree = "log --oneline --graph --all";
      };
    };
  };
}
