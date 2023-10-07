{ pkgs, ... }:
let
    customScripts = import ./scripts.nix pkgs;
in
{
    environment.systemPackages = with pkgs; [
        customScripts.upgrade
        neovim
        git
        wget
    ];
}