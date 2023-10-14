{ pkgs, ... }:
let
    customScripts = import ./scripts.nix pkgs;
in
{
    environment.systemPackages = with pkgs; [
        (libsForQt5.callPackage ./pkgs/xwaylandvideobridge.nix {})
#        customScripts.rebuild
        neovim
        git
        wget
	    btop
	    tree
    ];
}
