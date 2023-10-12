{ config, pkgs, lib, ... }:
{
    # Basic Hyprland configuration
    wayland.windowManager.hyprland.enable = true;
    wayland.windowManager.hyprland.extraConfig =
        builtins.readFile ./general.conf +
        builtins.readFile ./windowrules.conf +
        builtins.readFile ./workspacerules.conf +
        builtins.readFile ./keybinds.conf;

    # Link custom XKB file
    xdg.configFile."xkb/symbols/us-german".source = ./us-german.xkb;

    # Packages needed on Hyprland specifically, in addition to a standard desktop
    home.packages = with pkgs; [
        gnome.nautilus
        kitty
        ulauncher
    ];
}
