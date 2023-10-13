{ config, pkgs, lib, ... }:
{
    programs.neovim = {
        enable = true;
        defaultEditor = true;
        viAlias = true;
        vimAlias = true;

        extraConfig = builtins.readFile ./vimrc;
        extraLuaConfig = builtins.readFile ./neovim.lua;

        plugins = with pkgs.vimPlugins; [
            tokyonight-nvim
            
            nerdtree
            nvim-lspconfig
        ];
    };

    home.packages = with pkgs; [
        # Nix LSP
        nixd
    ];
}
