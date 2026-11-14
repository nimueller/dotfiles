{ config, dotfilesLink, ... }:
{
  xdg = {
    configFile = {
      "hypr".source = dotfilesLink "config/hypr";
      "kitty".source = dotfilesLink "config/kitty";
      "quickshell".source = dotfilesLink "config/quickshell";
      # Only the configuration: credentials, pairing state and logs stay out of git
      "sunshine/sunshine.conf".source = dotfilesLink "config/sunshine/sunshine.conf";
      "sunshine/apps.json".source = dotfilesLink "config/sunshine/apps.json";
      # Only the file: machine-specific rules (the Surface's speaker protection)
      # live next to it in ~/.config/wireplumber and must stay
      "wireplumber/wireplumber.conf.d/disable-headset-stand.conf".source =
        dotfilesLink "config/wireplumber/wireplumber.conf.d/disable-headset-stand.conf";
      "xdg-desktop-portal/hyprland-portals.conf".source =
        dotfilesLink "config/xdg-desktop-portal/hyprland-portals.conf";
    };
    dataFile = {
      # The backend that hyprland-portals.conf calls "nautilus"
      "xdg-desktop-portal/portals/nautilus.portal".source =
        dotfilesLink "config/xdg-desktop-portal/nautilus.portal";
      # Files opens "Open with Disks" and "Format…" through this name: the
      # shell's partition editor answers instead of GNOME Disks
      # (disk-utility.py). The session bus looks here before /usr/share, so
      # it wins over an installed GNOME Disks, too.
      "dbus-1/services/org.gnome.DiskUtility.service".text = ''
        [D-BUS Service]
        Name=org.gnome.DiskUtility
        Exec=${config.xdg.configHome}/quickshell/menus/disk-utility.py
      '';
    };
  };
}
