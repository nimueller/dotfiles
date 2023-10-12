{ pkgs, ... }:
{
    rebuild = pkgs.writeShellScriptBin "rebuild" ''
        sudo nixos-rebuild switch -I nixos-config="$HOME/dotfiles/configuration.nix"
    '';
}