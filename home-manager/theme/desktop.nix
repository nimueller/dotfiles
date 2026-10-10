{ pkgs, config, ... }:
let
  theme = {
    cursor = pkgs.bibata-cursors;
    cursor-theme-name = "Bibata-Modern-Ice";
    gtk-theme-name = "catppuccin-macchiato-blue-standard";
  };
in
{
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      cursor-theme = theme.cursor-theme-name;
    };
  };

  home.pointerCursor = {
    enable = true;
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
    gtk4.theme = config.gtk.theme;
  };
}
