{ config, ... }:
{
  xdg.configFile = {
    "hypr".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/hypr";
    "kitty".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/kitty";
    "brave-flags.conf".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/brave-flags.conf";
    "quickshell".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/quickshell";
    # Only the configuration: credentials, pairing state and logs stay out of git
    "sunshine/sunshine.conf".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/sunshine/sunshine.conf";
    "sunshine/apps.json".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/sunshine/apps.json";
    "xdg-desktop-portal/hyprland-portals.conf".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/xdg-desktop-portal/hyprland-portals.conf";
  };
  # The backend that hyprland-portals.conf calls "nautilus"
  xdg.dataFile."xdg-desktop-portal/portals/nautilus.portal".source =
    config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/xdg-desktop-portal/nautilus.portal";
}
