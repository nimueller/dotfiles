{ dotfilesLink, ... }:
{
  xdg.configFile = {
    "hypr".source = dotfilesLink "config/hypr";
    "kitty".source = dotfilesLink "config/kitty";
    "quickshell".source = dotfilesLink "config/quickshell";
    # Only the configuration: credentials, pairing state and logs stay out of git
    "sunshine/sunshine.conf".source = dotfilesLink "config/sunshine/sunshine.conf";
    "sunshine/apps.json".source = dotfilesLink "config/sunshine/apps.json";
    "wireplumber".source = dotfilesLink "config/wireplumber";
    "xdg-desktop-portal/hyprland-portals.conf".source =
      dotfilesLink "config/xdg-desktop-portal/hyprland-portals.conf";
  };
  # The backend that hyprland-portals.conf calls "nautilus"
  xdg.dataFile."xdg-desktop-portal/portals/nautilus.portal".source =
    dotfilesLink "config/xdg-desktop-portal/nautilus.portal";
}
