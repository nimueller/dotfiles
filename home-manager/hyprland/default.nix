{ config, pkgs, lib, ... }:
{
    # Basic Hyprland configuration
    wayland.windowManager.hyprland.enable = true;
    wayland.windowManager.hyprland.extraConfig =
        builtins.readFile ./hypr/general.conf +
        builtins.readFile ./hypr/windowrules.conf +
        builtins.readFile ./hypr/workspacerules.conf +
        builtins.readFile ./hypr/keybinds.conf + 
        builtins.readFile ./hypr/autostart.conf;

    # Link custom XKB file
    xdg.configFile."xkb/symbols/us-german".source = ./hypr/us-german.xkb;
    xdg.configFile."hypr/hyprpaper.conf".source = ./hypr/hyprpaper.conf;
    xdg.configFile."hypr/wallpaper.jpg".source = builtins.fetchurl {
        url = "https://raw.githubusercontent.com/saint-13/Linux_Dynamic_Wallpapers/main/Dynamic_Wallpapers/ZorinMountainFog/ZorinMountainFog1.jpg";
        sha256 = "1l2rvpyn2ab7cd1y93v3im3ki8dhrlcwar30lb4kyl078pxh52kd";
    };

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

        (eww-wayland.overrideAttrs (old: {
            src = pkgs.fetchFromGitHub {
                owner = "ralismark";
                repo = "eww";
                rev = "tray-3";
                hash = "sha256-GEysmNDm+olt1WXHzRwb4ZLifkXmeP5+APAN3b81/Og=";
            };
        }))

        # GUI apps
        gnome.adwaita-icon-theme
        gnome.nautilus
        ulauncher
    ];
}
