{ pkgs, ... }:
{
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
    nixfmt
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
    vscode-langservers-extracted
    eslint
    prisma
    typescript-language-server

    # Hyprland
    hyprls

    # Docker
    docker-compose-language-service

    # Bash
    bash-language-server

    # Python
    pyright

    # Go
    go
    gopls
  ];
}
