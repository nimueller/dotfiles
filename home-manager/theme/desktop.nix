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
    thunderbird_theme=${config.xdg.dataHome}/thunderbird-gnome-theme

    # thunderbird_link <profile> <name> <target>
    thunderbird_link() {
      local link=$1/$2
      if [ -e "$link" ] && [ ! -L "$link" ]; then
        warnEcho "Thunderbird theme: $link exists, left as it is"
        return
      fi
      run ln -sfn "$3" "$link"
    }

    # The profile folders in <root>/profiles.ini; relative ones are below root
    thunderbird_profiles() {
      local root=$1 path
      sed -n 's/^Path=//p' "$root/profiles.ini" | while IFS= read -r path; do
        case $path in
          /*)
            echo "$path"
            ;;
          *)
            echo "$root/$path"
            ;;
        esac
      done
    }

    # thunderbird_theme_profiles <root>: the theme in every profile of a root
    thunderbird_theme_profiles() {
      local root=$1 profile
      if [ ! -f "$root/profiles.ini" ]; then
        return
      fi
      thunderbird_profiles "$root" | while IFS= read -r profile; do
        if [ -d "$profile" ]; then
          thunderbird_link "$profile" chrome "$thunderbird_theme"
          thunderbird_link "$profile" user.js "$thunderbird_theme/configuration/user.js"
        fi
      done
    }

    for root in "${config.xdg.configHome}/thunderbird" "$HOME/.thunderbird"; do
      thunderbird_theme_profiles "$root"
    done
  '';
}
