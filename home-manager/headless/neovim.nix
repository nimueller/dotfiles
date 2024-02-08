{ config, pkgs, inputs, ... }:
{
  nixpkgs.overlays = [
    inputs.neovim-nightly-overlay.overlay
  ];

  programs.neovim.enable = true;

  xdg.configFile."nvim/init.lua".source = ../../config/nvim/init.lua;
  xdg.configFile."nvim/lua".source = ../../config/nvim/lua;

  home.packages = with pkgs; [
    # neovim plugin package dependencies
    ripgrep
    fd
    tree-sitter

    ## language servers
    # Lua
    luaPackages.luacheck
    lua-language-server
    stylua

    # Nix
    nixpkgs-fmt
    nil
    statix

    # XML/HTML
    lemminx
    html-tidy

    # Kotlin/Java
    jdt-language-server
    kotlin-language-server
    ktlint

    # LaTeX
    texliveFull
    evince
    texlab
    ltex-ls

    # JavaScript/TypeScript
    biome
    nodePackages.vscode-langservers-extracted
    nodePackages.eslint
    nodePackages.prisma
    nodePackages."@prisma/language-server"
    nodePackages.typescript-language-server

    # Docker
    docker-compose-language-service

    # Bash
    nodePackages.bash-language-server
  ];
}
