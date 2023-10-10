{ pkgs, ... }:
let
    customScripts = import ./scripts.nix pkgs;
in
{
    environment.systemPackages = with pkgs; [
        customScripts.rebuild
        neovim
        git
        wget
	    kitty
	    btop
	    tree
    ];
}
