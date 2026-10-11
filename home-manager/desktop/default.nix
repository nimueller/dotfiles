{ config, pkgs, lib, ... }:
let
  my-pkgs = import ../../pkgs { inherit pkgs; };
in
{
  targets.genericLinux.enable = true;

  imports = [
    ./gaming.nix
    ./symlinks.nix
    ../theme/desktop.nix
  ];

  dconf.settings = {
    "com/github/stunkymonkey/nautilus-open-any-terminal" = {
      terminal = "kitty";
    };
  };

  services.kdeconnect.enable = true;

  # The bar, launcher, notifications and the volume/brightness OSD come from
  # the resident quickshell daemon (config/quickshell/menus/daemon.qml).
  # Hyprland starts it; D-Bus activation also starts it (instead of dunst)
  # when a notification arrives while it isn't running.
  systemd.user.services.quickshell-daemon = {
    Unit = {
      Description = "Quickshell bar, launcher, notifications and OSD";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "dbus";
      BusName = "org.freedesktop.Notifications";
      ExecStart = "${pkgs.quickshell}/bin/qs -n -p ${config.dotfiles}/config/quickshell/menus/daemon.qml";
      Restart = "on-failure";
    };
  };
  # Same file name as dunst's, so it takes precedence over /usr/share
  xdg.dataFile."dbus-1/services/org.knopwob.dunst.service".text = ''
    [D-BUS Service]
    Name=org.freedesktop.Notifications
    Exec=/bin/false
    SystemdService=quickshell-daemon.service
  '';
  # Mask dunst's own unit in case anything asks for it directly
  xdg.configFile."systemd/user/dunst.service".source = config.lib.file.mkOutOfStoreSymlink "/dev/null";

  # Desktop notifications for calendar reminders (VALARMs of the calendars
  # enabled in the quickshell calendar menu), checked every minute
  systemd.user.services.quickshell-calendar-reminders = {
    Unit.Description = "Calendar reminders for the quickshell calendar menu";
    Service = {
      Type = "oneshot";
      ExecStart = "${my-pkgs.quickshell-calendar-python}/bin/quickshell-calendar-python %h/.config/quickshell/menus/calendar-dav.py remind";
      Environment = "PATH=${lib.makeBinPath [ pkgs.libsecret pkgs.libnotify ]}:/usr/bin";
    };
  };
  systemd.user.timers.quickshell-calendar-reminders = {
    Unit.Description = "Check calendar reminders every minute";
    Timer = {
      OnCalendar = "minutely";
      AccuracySec = "5s";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  fonts.fontconfig.enable = true;

  # Packages needed on Hyprland specifically, in addition to a standard desktop
  home.packages = with pkgs; [
    nerd-fonts.noto
    noto-fonts
    noto-fonts-lgc-plus
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-emoji-blob-bin
    noto-fonts-color-emoji
    noto-fonts-monochrome-emoji

    rofi

    xdg-terminal-exec
    playerctl
    hyprpicker
    hyprshot # screenshots; brings grim, slurp, jq etc. along
    slurp
    libnotify
    libsecret
    wtype
    cliphist
    pavucontrol
    quickshell # bar, menus, launcher, notifications, OSD (config/quickshell/menus)

    my-pkgs.recorder
    my-pkgs.quickshell-calendar-python
    my-pkgs.init-tex
    my-pkgs.edit-tex

    # Gnome GUI apps
    adwaita-icon-theme
    evince # PDF viewer
    eog # Image viewer
    gnome-characters # Emoji picker
    gnome-font-viewer
    dconf-editor
    file-roller
    seahorse # Manage keyring
    geary
    # Other GUI apps
    keepassxc
    wl-clipboard
    wf-recorder
  ];
}
