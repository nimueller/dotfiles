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
    # Spell checker
    codebook

    # LaTeX
    texliveFull
    evince
    texlab
    ltex-ls

    # Markdown
    marksman

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
