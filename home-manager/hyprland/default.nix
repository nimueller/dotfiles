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
            font_family = "Jet Brains Mono";
            foreground = "#BCC6F1";
            background = "#24283B";
            show_hyperlink_targets = true;
            copy_on_select = "clipboard";
            strip_trailing_spaces = "smart";
            focus_follows_mouse = true;
        };
    };

    # Sway On-Screen-Display for volume feedback
    services.swayosd.enable = true;

    # Packages needed on Hyprland specifically, in addition to a standard desktop
    home.packages = with pkgs; [
        # Utility
        playerctl
        hyprpaper
        hyprpicker

        # GUI apps
        gnome.nautilus
        ulauncher
    ];
}
