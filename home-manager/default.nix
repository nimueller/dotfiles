{ config, pkgs, lib, ... }:
{
    programs.home-manager.enable = true;

    home.username = "nico";
    home.homeDirectory = "/home/nico";
    home.stateVersion = "23.05";

    home.packages = with pkgs; [
        btop
    ];
}