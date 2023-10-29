{ config, pkgs, lib, stdenv, ... }:
let
    my-pkgs = import ../pkgs { inherit pkgs lib; };
in
{
    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
        "idea-ultimate"
	    "spotify"
        "vscode"
        "discord"
    ];

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
    # xdg.configFile."hypr/recorder.sh".source = ./recorder.sh;
    # xdg.configFile."hypr/applauncher.sh".source = ./applauncher.sh;
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
        keybindings = {
            "ctrl+v" = "paste_from_clipboard";
        };
        extraConfig = ''
        mouse_map right click grabbed paste_from_clipboard
        '';
    };

    # Sway On-Screen-Display for volume feedback
    services.swayosd.enable = true;

    # Dunst as notification daemon
    services.dunst = {
        enable = true;

        settings = {
            global = {
                monitor = 0;
                font = "JetBrainsMono 12";
            };
        };
    };

    fonts.fontconfig.enable = true;

    # Packages needed on Hyprland specifically, in addition to a standard desktop
    home.packages = with pkgs; [
        (nerdfonts.override { fonts = [ "JetBrainsMono" ]; })

        # Utility
        playerctl
        hyprpaper
        hyprpicker
        grim
        slurp
        jq
        libnotify

        my-pkgs.hyprshot
        my-pkgs.eww-wayland-tray
        my-pkgs.recorder
        my-pkgs.applauncher

        # GUI apps
        gnome.adwaita-icon-theme
        gnome.nautilus # File explorer
        gnome.evince # PDF viewer
        gnome.eog # Image viewer
        gnome.totem # Video player
        gnome.gnome-font-viewer
        nautilus-open-any-terminal
        ulauncher
        keepassxc
        brave
        discord
        jetbrains.idea-ultimate
        spotify
        wl-clipboard
        wf-recorder
    ];

    # Theming
    dconf.settings = {
        "org/gnome/desktop/interface" = {
            color-scheme = "prefer-dark";
            cursor-theme = "Bibata-Modern-Ice";
        };
    };

    home.pointerCursor = {
        name = "Bibata-Modern-Ice";
        package = pkgs.bibata-cursors;
        size = 64;
        gtk.enable = true;
        x11.enable = true;
    };

    gtk.cursorTheme.name = "Bibata-Modern-Ice";
}
