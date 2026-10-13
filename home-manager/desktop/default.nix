{
  config,
  pkgs,
  lib,
  ...
}:
let
  my-pkgs = import ../../pkgs { inherit pkgs; };
in
{
  targets.genericLinux.enable = true;

  imports = [
    ./gaming.nix
    ./symlinks.nix
    ../dev
    ../theme/desktop.nix
  ];

  dconf.settings = {
    "com/github/stunkymonkey/nautilus-open-any-terminal" = {
      terminal = "kitty";
    };
  };

  services.kdeconnect.enable = true;

  systemd.user = {
    # Hyprland isn't started by a session manager, so nothing brought up
    # graphical-session.target and the services that need it (the GNOME
    # portal's file chooser, kdeconnect) didn't start. Hyprland starts this
    # target once the environment is imported (config/hypr/autostart.lua).
    targets.hyprland-session.Unit = {
      Description = "Hyprland session";
      BindsTo = [ "graphical-session.target" ];
      Wants = [ "graphical-session-pre.target" ];
      After = [ "graphical-session-pre.target" ];
    };

    # The bar, launcher, notifications and the volume/brightness OSD come
    # from the resident quickshell daemon (config/quickshell/menus/daemon.qml).
    # Hyprland starts it; D-Bus activation also starts it (instead of dunst)
    # when a notification arrives while it isn't running.
    services.quickshell-daemon = {
      Unit = {
        Description = "Quickshell bar, launcher, notifications and OSD";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "dbus";
        BusName = "org.freedesktop.Notifications";
        ExecStart = "/usr/bin/qs -n -p ${config.dotfiles}/config/quickshell/menus/daemon.qml"; # from pacman (system/packages/session.txt)
        Restart = "on-failure";
      };
    };

    # Desktop notifications for calendar reminders (VALARMs of the calendars
    # enabled in the quickshell calendar menu), checked every minute
    services.quickshell-calendar-reminders = {
      Unit.Description = "Calendar reminders for the quickshell calendar menu";
      Service = {
        Type = "oneshot";
        ExecStart = "${my-pkgs.quickshell-calendar-python}/bin/quickshell-calendar-python %h/.config/quickshell/menus/calendar-dav.py remind";
        Environment = "PATH=${
          lib.makeBinPath [
            pkgs.libsecret
            pkgs.libnotify
          ]
        }:/usr/bin";
      };

    };
    timers.quickshell-calendar-reminders = {
      Unit.Description = "Check calendar reminders every minute";
      Timer = {
        OnCalendar = "minutely";
        AccuracySec = "5s";
      };
      Install.WantedBy = [ "timers.target" ];

    };
  };

  xdg = {
    # The settings app for this machine's own settings (config/hypr/local.lua)
    desktopEntries.machine-settings = {
      name = "Machine Settings";
      comment = "Displays, environment variables and autostart programs of this machine";
      exec = "${config.dotfiles}/config/quickshell/menus/toggle.sh settings";
      icon = "preferences-desktop-display";
      categories = [ "Settings" ];
    };

    # Pear Desktop (pacman) as "YouTube Music", like its window title: the
    # launcher, the sound menu and the window details take the name from
    # here. Same id as the package's entry; ~/.nix-profile comes before /usr
    # in XDG_DATA_DIRS, so this one wins.
    desktopEntries."com.github.th-ch.youtube-music" = {
      name = "YouTube Music";
      comment = "YouTube Music Desktop App - including custom plugins";
      exec = "pear-desktop";
      icon = "com.github.th-ch.youtube-music";
      categories = [ "AudioVideo" ];
      settings.StartupWMClass = "com.github.th-ch.youtube-music";
    };

    # For the launcher's emoji search (config/quickshell/menus/Launcher.qml)
    dataFile."quickshell-launcher/emoji.json".source = my-pkgs.quickshell-emoji;

    # Same file name as dunst's, so it takes precedence over /usr/share
    dataFile."dbus-1/services/org.knopwob.dunst.service".text = ''
      [D-BUS Service]
      Name=org.freedesktop.Notifications
      Exec=/bin/false
      SystemdService=quickshell-daemon.service
    '';
    # Mask dunst's own unit in case anything asks for it directly
    configFile."systemd/user/dunst.service".source = config.lib.file.mkOutOfStoreSymlink "/dev/null";
  };

  fonts.fontconfig.enable = true;

  # Packages needed on Hyprland specifically, in addition to a standard desktop
  home.packages = with pkgs; [
    nerd-fonts.noto # the quickshell menus' font
    nerd-fonts.caskaydia-cove # the quickshell bar's font
    noto-fonts
    noto-fonts-lgc-plus
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-emoji-blob-bin
    noto-fonts-color-emoji
    noto-fonts-monochrome-emoji

    xdg-terminal-exec
    playerctl
    hyprpicker
    grim # screenshots (config/quickshell/menus/screenshot.sh)
    imagemagick
    libnotify
    libsecret
    cliphist
    pavucontrol

    my-pkgs.stay-awake # keeps the screen awake for Sunshine streams (config/sunshine)
    my-pkgs.after-unlock # autostarts that need the keyring (config/hypr/autostart.lua)
    my-pkgs.quickshell-calendar-python
    my-pkgs.init-tex
    my-pkgs.edit-tex

    # Gnome GUI apps
    adwaita-icon-theme
    evince # PDF viewer
    eog # Image viewer
    gnome-characters # Emoji picker
    gnome-font-viewer
    marktext # Markdown, rendered: GFM, KaTeX, Mermaid, GitLab mode; opens .md files
    dconf-editor
    file-roller
    seahorse # Manage keyring
    # Other GUI apps
    keepassxc
    wl-clipboard
  ];
}
