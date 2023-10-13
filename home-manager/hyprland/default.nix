{ config, pkgs, lib, ... }:
{
    # Basic Hyprland configuration
    wayland.windowManager.hyprland.enable = true;
    wayland.windowManager.hyprland.extraConfig =
        builtins.readFile ./hypr/general.conf +
        builtins.readFile ./hypr/windowrules.conf +
        builtins.readFile ./hypr/workspacerules.conf +
        builtins.readFile ./hypr/keybinds.conf;

    # Link custom XKB file
    xdg.configFile."xkb/symbols/us-german".source = ./hypr/us-german.xkb;

    # Use kitty as terminal emulator
    programs.kitty = {
        enable = true;
        settings = {
            show_hyperlink_targets = true;
            copy_on_select = "clipboard";
            strip_trailing_spaces = "smart";
            focus_follows_mouse = true;
        };
    };

    # Sway On-Screen-Display for volume feedback and playerctl to control media playback using media keys
    services.swayosd.enable = true;
    services.playerctld.enable = true;

    # Packages needed on Hyprland specifically, in addition to a standard desktop
    home.packages = with pkgs; [
        gnome.nautilus
        ulauncher
    ];
}
