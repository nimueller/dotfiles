{
  pkgs,
  lib,
  username,
  config,
  ...
}:
let
  signingKey = "~/.ssh/id_rsa_github.pub";
  allowedSigners = "${config.xdg.configHome}/git/allowed_signers";
in
{
  # Basic Home Manager settings
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

  imports = [
    ./neovim.nix
    ./symlinks.nix
    ../theme/default.nix
  ];

  home = {
    inherit username;
    homeDirectory = "/home/${username}";
    stateVersion = "23.05";

    packages = with pkgs; [
      # Terminal programs
      fzf # Lifesaver!
      autojump # Lifesaver #2!
      tldr
      lsd
      jq
      lua
      tree
    ];

    file.".p10k.zsh".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/zsh/p10k.zsh";
    # Claude Code's instructions for every project
    file.".claude/CLAUDE.md".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/claude/CLAUDE.md";
  };

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
        key = signingKey;
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
        diff.algorithm = "histogram";
        merge.conflictStyle = "zdiff3";
        push.autoSetupRemote = true;
        pull.rebase = true;
        rebase.autoStash = true;
        fetch.prune = true;
        rerere.enabled = true;
        # `git log --show-signature` verifies the own commits (activation below)
        gpg.ssh.allowedSignersFile = allowedSigners;

        alias = {
          tree = "log --oneline --graph --all";
        };
      };

      ignores = [
        "*~"
        "*.swp"
        ".direnv/"
        ".claude/settings.local.json"
      ];

      # Identities that belong to one machine (another account's name, email
      # and signing key for some directories, with includeIf "gitdir:...")
      # go into this untracked file; it's included last, so it wins
      includes = [ { path = "~/.config/git/config.local"; } ];
    };

    # Syntax-highlighted diffs in git diff, log -p and show
    delta = {
      enable = true;
      enableGitIntegration = true;
      options = {
        navigate = true; # n / N jump between files
        line-numbers = true;
      };
    };

    gh = {
      enable = true;
      settings.git_protocol = "ssh";
    };
  };

  # Git's list of trusted signing keys, made from the signing key's public
  # half where this machine has it. Not in the repository: the key belongs
  # to the machine, and the runner in CI has none.
  home.activation.gitAllowedSigners = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    key=${lib.replaceStrings [ "~" ] [ config.home.homeDirectory ] signingKey}
    if [[ -f $key && ! -v DRY_RUN ]]; then
      mkdir -p "$(dirname ${allowedSigners})"
      printf '%s namespaces="git" %s\n' ${lib.escapeShellArg config.programs.git.settings.user.email} \
        "$(cut -d' ' -f1,2 "$key")" > ${allowedSigners}
    fi
  '';
}
