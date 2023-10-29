{ pkgs, ... }:
let
    theme = {
        cursor = pkgs.bibata-cursors;
        cursor-theme-name = "Bibata-Modern-Ice";
        gtk-theme-name = "Catppuccin-Macchiato-Standard-Blue-Dark";

        hyprland = pkgs.fetchFromGitHub {
            owner = "catppuccin";
            repo = "hyprland";
            rev = "v1.2";
            sha256 = "07B5QmQmsUKYf38oWU3+2C6KO4JvinuTwmW1Pfk8CT8=";
        };

    };
in
{
    wayland.windowManager.hyprland.extraConfig = builtins.readFile "${theme.hyprland}/themes/macchiato.conf";

    programs.kitty.theme = "Catppuccin-Macchiato";

    dconf.settings = {
        "org/gnome/desktop/interface" = {
            color-scheme = theme.gtk-theme-name;
            cursor-theme = theme.cursor-theme-name;
        };
    };

    home.pointerCursor = {
        name = theme.cursor-theme-name;
        package = theme.cursor;
        size = 64;
        gtk.enable = true;
        x11.enable = true;
    };

    home.sessionVariables = {
        GTK_THEME = theme.gtk-theme-name;
    };

    gtk = {
        enable = true;
        cursorTheme.name = theme.cursor-theme-name;
        theme = {
            name = theme.gtk-theme-name;
            package = pkgs.catppuccin-gtk.override {
                variant = "macchiato";
            };
        };
    };

    # Wallpaper
    xdg.configFile."hypr/wallpaper.jpg".source = builtins.fetchurl {
        url = "https://raw.githubusercontent.com/saint-13/Linux_Dynamic_Wallpapers/main/Dynamic_Wallpapers/ZorinMountainFog/ZorinMountainFog1.jpg";
        sha256 = "1l2rvpyn2ab7cd1y93v3im3ki8dhrlcwar30lb4kyl078pxh52kd";
    };

}
