{
  pkgs,
  config,
  lib,
  ...
}:
let
  theme = {
    cursor = pkgs.bibata-cursors;
    cursor-theme-name = "Bibata-Modern-Ice";
    gtk-theme-name = "catppuccin-macchiato-blue-standard";
    # Adwaita look for Thunderbird: userChrome.css, not an add-on, so it can't
    # be picked in Thunderbird's settings
    thunderbird = pkgs.fetchFromGitHub {
      owner = "rafaelmardojai";
      repo = "thunderbird-gnome-theme";
      rev = "c61b897554b5631c042c5e3c4b76cc021a9890b7";
      hash = "sha256-BB0V/tvTBEPIpS+UKzQUUjQIRuHxLVAxF+anZW4vH5c=";
    };
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

  # Thunderbird (from pacman) reads the theme only from each profile's chrome
  # folder, with the prefs from its user.js turned on. Profile folders have
  # random names, so the links go into every profile in profiles.ini; a
  # profile created later gets them with the next switch. A chrome folder or
  # user.js of its own is left alone.
  xdg.dataFile."thunderbird-gnome-theme".source = theme.thunderbird;
  home.activation.thunderbirdTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    theme=${config.xdg.dataHome}/thunderbird-gnome-theme
    for root in "${config.xdg.configHome}/thunderbird" "$HOME/.thunderbird"; do
      [ -f "$root/profiles.ini" ] || continue
      sed -n 's/^Path=//p' "$root/profiles.ini" | while IFS= read -r path; do
        case $path in /*) profile=$path ;; *) profile=$root/$path ;; esac
        [ -d "$profile" ] || continue
        for link in "chrome:$theme" "user.js:$theme/configuration/user.js"; do
          target=$profile/''${link%%:*}
          if [ -e "$target" ] && [ ! -L "$target" ]; then
            warnEcho "Thunderbird theme: $target exists, left as it is"
          else
            run ln -sfn "''${link#*:}" "$target"
          fi
        done
      done
    done
  '';
}
