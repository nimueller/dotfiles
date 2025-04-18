{ pkgs, ... }:
{
  programs.neovim.enable = true;
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

    # C/C++
    sourcekit-lsp

    # Kotlin/Java
    jdt-language-server
    kotlin-language-server
    ktlint

    # LaTeX
    # texliveFull
    # evince
    # texlab
    # ltex-ls

    # JavaScript/TypeScript
    biome
    nodePackages.vscode-langservers-extracted
    nodePackages.eslint
    # nodePackages.prisma
    # nodePackages."@prisma/language-server"
    nodePackages.typescript-language-server

    # Docker
    docker-compose-language-service

    # Bash
    # nodePackages.bash-language-server
  ];
}
