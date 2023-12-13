{ config, pkgs, lib, stdenv, inputs, ... }:
let
    my-pkgs = import ../../pkgs { inherit pkgs lib; };
in
{
    nixpkgs.config.allowUnfree = true;

    imports = [ 
        inputs.hyprland.homeManagerModules.default
        inputs.ags.homeManagerModules.default
        inputs.spicetify-nix.homeManagerModule
        ../headless
        ../theme/desktop.nix
    ];

    # Basic Hyprland configuration
    wayland.windowManager.hyprland = {
        enable = true;
        extraConfig =
            builtins.readFile ../../config/hypr/general.conf +
            builtins.readFile ../../config/hypr/windowrules.conf +
            builtins.readFile ../../config/hypr/workspacerules.conf +
            builtins.readFile ../../config/hypr/keybinds.conf + 
            builtins.readFile ../../config/hypr/autostart.conf;
    };

    # Link custom XKB file
    xdg.configFile."xkb/symbols/us-german".source = ../../config/hypr/us-german.xkb;
    xdg.configFile."hypr/hyprpaper.conf".source = ../../config/hypr/hyprpaper.conf;

    # Use kitty as terminal emulator
    programs.kitty = {
        enable = true;
        settings = {
            font_family = "Jet Brains Mono";
            show_hyperlink_targets = true;
            copy_on_select = "clipboard";
            strip_trailing_spaces = "smart";
            focus_follows_mouse = true;
        };
        keybindings = {
            "ctrl+v" = "paste_from_clipboard";
        };
    };

    # Sway On-Screen-Display for volume feedback
    services.swayosd.enable = true;

    # Dunst as notification daemon
    services.dunst = {
        enable = true;

        settings = {
            global = {
                monitor = 0;
                format = "<b>%s</b>\\n%b\\n%p";
                vertical_alignment = "top";
            };
        };
    };

    programs.spicetify.enable = true;

    programs.ags = {
        enable = true;
        extraPackages = [ pkgs.libsoup_3 ];
    };

    programs.rofi = {
        enable = true;
        package = pkgs.rofi-wayland;
        extraConfig = {
            modi = "combi,calc";
            combi-modes = "drun,ssh";
            show-icons = true;
            drun-display-format = "{icon} {name}";
            display-combi = " 󱓞 Launch ";
            display-calc = " 󰃬 Calc ";
            display-drun = " App";
            display-ssh = " 󱘖 SSH";
        };
        plugins = [
            pkgs.rofi-calc
        ];
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
        inotify-tools

        my-pkgs.hyprshot
        my-pkgs.eww-wayland-tray
        my-pkgs.xwaylandvideobridge
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
        keepassxc
        brave
        firefox
        discord-canary
        jetbrains.idea-ultimate
        wl-clipboard
        wf-recorder
    ];
}
