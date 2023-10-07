{ pkgs, ... }:
{
    upgrade = pkgs.writeShellScriptBin "upgrade" ''
        sudo nixos-rebuild switch -I nixos-config="$HOME/dotfiles/configuration.nix"
    '';
}