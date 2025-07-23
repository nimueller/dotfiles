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
  wayland.windowManager.hyprland.extraConfig = builtins.readFile "${theme.hyprland}/themes/macchiato.conf" + ''
    env = GTK_THEME, ${theme.gtk-theme-name}
  '';

  programs.kitty.themeFile = "Catppuccin-Macchiato";

  services.dunst = {
    iconTheme = {
      package = pkgs.papirus-icon-theme;
      name = "Papirus";
    };

    settings = {
      global = {
        font = "NotoMono Nerd Font 12";
        frame_width = 2;
        corner_radius = 10;
        frame_color = "#8AADF4";
        separator_color = "frame";
      };

      urgency_low = {
        background = "#24273A";
        foreground = "#CAD3F5";
      };

      urgency_normal = {
        background = "#24273A";
        foreground = "#CAD3F5";
      };

      urgency_critical = {
        background = "#24273A";
        foreground = "#CAD3F5";
        frame_color = "#F5A97F";
      };
    };
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      cursor-theme = theme.cursor-theme-name;
    };
  };

  home.pointerCursor = {
    name = theme.cursor-theme-name;
    package = theme.cursor;
    gtk.enable = true;
    x11.enable = true;
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
  home.packages = with pkgs; [
    kdePackages.breeze-gtk
  ];

}
