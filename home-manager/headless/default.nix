{ pkgs, username, ... }:
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
    zsh
  ];

  imports = [
    ./neovim.nix
    ./symlinks.nix
    ../theme/default.nix
  ];

  programs = {
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
        format = "ssh";
      };
      extraConfig = {
        init.defaultBranch = "main";
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
