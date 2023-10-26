{ config, pkgs, lib, stdenv, ... }:
let
    hyprshot = pkgs.stdenv.mkDerivation rec {
        name = "hyprshot";
        version = "1.2.3";

        src = builtins.fetchurl {
            url = "https://github.com/Gustash/Hyprshot/archive/refs/tags/${version}.tar.gz";
            sha256 = "03ppmj44vg28vq3m7f0igg3i6x97gmr6mj1nqd05kxwksznlxqq1";
        };

        installPhase = "mkdir -p $out/bin; cp hyprshot $out/bin";
    };
    recorder = pkgs.writeShellScriptBin "recorder" (builtins.readFile ./recorder.sh);
in
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
    xdg.configFile."hypr/recorder.sh".source = ./recorder.sh;
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

    # Packages needed on Hyprland specifically, in addition to a standard desktop
    home.packages = with pkgs; [
        # Utility
        playerctl
        hyprpaper
        hyprpicker
        grim
        slurp
        jq
        libnotify
        hyprshot
        recorder

        # Custom EWW fork for working system tray
        (eww-wayland.overrideAttrs (drv: rec {
          version = "tray-3";
          src = fetchFromGitHub {
            owner = "ralismark";
            repo = "eww";
            rev = "a82ed62c25ba50f28dc8c3d57efe440d51d6136b";
            sha256 = "sha256-vxMGAa/RTsMADPK4dM/28SV2ktCT0DenYvGsHZ4IJ8c=";
          };
          cargoDeps = drv.cargoDeps.overrideAttrs (lib.const {
            inherit src;
            outputHash = "sha256-3B81cTIVt/cne6I/gKBgX4zR5w0UU60ccrFGV1nNCoA=";
          });
          buildInputs = drv.buildInputs ++ (with pkgs; [ glib librsvg libdbusmenu-gtk3 ]);
        }))

        # GUI apps
        gnome.adwaita-icon-theme
        gnome.nautilus
        ulauncher
    ];
}
