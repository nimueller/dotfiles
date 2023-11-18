{ config, pkgs, lib, ... }:
{
    home.packages = with pkgs; [
        # neovim plugin package dependencies
        ripgrep

        ## language servers
        # Lua
        lua-language-server
        # Nix
        nixd
        # JavaScript/TypeScript
        nodePackages.vscode-langservers-extracted
        nodePackages.eslint
        nodePackages.typescript-language-server
    ];
}
