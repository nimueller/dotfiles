{ config, pkgs, lib, ... }:
{
    programs.neovim.enable = true;

    xdg.configFile.nvim.source = ../../config/nvim;

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
        # Bash
        nodePackages.bash-language-server
    ];
}
