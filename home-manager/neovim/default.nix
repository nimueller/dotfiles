{ config, pkgs, lib, ... }:
{
    home.packages = with pkgs; [
        # neovim plugin package dependencies
        ripgrep

        # language servers
        lua-language-server
        nixd
    ];
}
