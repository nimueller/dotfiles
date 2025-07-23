{ pkgs, ... }:
{
  programs.neovim.enable = true;
  home.packages = with pkgs; [
    # neovim plugin package dependencies
    luarocks
    ripgrep
    fd
    tree-sitter

    ## language servers
    # General
    codebook
    editorconfig-checker

    # LaTeX
    texliveFull
    evince
    texlab
    ltex-ls

    # Markdown
    marksman
    markdownlint-cli2

    # Lua
    luaPackages.luacheck
    lua-language-server
    stylua

    # Nix
    nixfmt-classic
    nil
    statix
    deadnix

    # XML/HTML
    lemminx
    html-tidy

    # C/C++
    clang-tools

    # Kotlin/Java
    jdt-language-server
    kotlin-language-server
    ktlint

    # JavaScript/TypeScript
    biome
    nodePackages.vscode-langservers-extracted
    nodePackages.eslint
    nodePackages.prisma
    nodePackages.typescript-language-server

    # Docker
    docker-compose-language-service

    # Bash
    nodePackages.bash-language-server
  ];
}
