{ config, pkgs, lib, ... }:
{
    programs.neovim.enable = true;

    xdg.configFile."nvim/init.lua".source = ../../config/nvim/init.lua;
    xdg.configFile."nvim/lua".source = ../../config/nvim/lua;

    home.packages = with pkgs; [
        # neovim plugin package dependencies
        ripgrep

        ## language servers
        # Lua
        lua-language-server
        # Nix
        nixd

        # LaTeX
        texlab
        ltex-ls

        # JavaScript/TypeScript
        nodePackages.vscode-langservers-extracted
        nodePackages.eslint
        nodePackages.typescript-language-server
        # Bash
        nodePackages.bash-language-server
    ];
}
