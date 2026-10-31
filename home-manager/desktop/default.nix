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
    ./flatpak.nix
    ./gaming.nix
    ./symlinks.nix
    ../dev
    ../theme/desktop.nix
  ];

  dconf.settings = {
    "com/github/stunkymonkey/nautilus-open-any-terminal" = {
      terminal = "kitty";
    };
    # Not the on-screen keyboard's screen-keyboard-enabled: the touch mode
    # sets it, by the tablet mode switch (config/hypr/modes.lua), and a value
    # here would turn it on again with every switch, also in laptop mode
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

    services = {
      # The bar, launcher, notifications and the volume/brightness OSD come
      # from the resident quickshell daemon (config/quickshell/menus/daemon.qml).
      # Hyprland starts it; D-Bus activation also starts it (instead of dunst)
      # when a notification arrives while it isn't running.
      quickshell-daemon = {
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

      # Nautilus, started with the session and kept running: a cold start
      # delayed the file chooser (config/xdg-desktop-portal) and SUPER + E.
      # Same bus name as its D-Bus activation, which starts this instead
      # (dataFile below). The preload also keeps the portal from waiting for
      # it while both start (nautilus-preload.c).
      nautilus = {
        Unit = {
          Description = "Nautilus, kept running";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          Type = "dbus";
          BusName = "org.gnome.Nautilus";
          ExecStart = "/usr/bin/nautilus --gapplication-service"; # from pacman (system/packages/session.txt)
          Environment = "LD_PRELOAD=${my-pkgs.nautilus-preload}/lib/nautilus-preload.so";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      # Desktop notifications for calendar reminders (VALARMs of the calendars
      # enabled in the quickshell calendar menu), checked every minute
      quickshell-calendar-reminders = {
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

      # Discord's WebRTC logs of calls, kept beyond its last sessions to look
      # into lag later (pkgs/scripts/discord-call-logs.py)
      discord-call-logs = {
        Unit.Description = "Keep Discord's logs of calls";
        Service = {
          Type = "oneshot";
          ExecStart = "${my-pkgs.discord-call-logs}/bin/discord-call-logs";
          Nice = 19;
          IOSchedulingClass = "idle";
        };
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
    # Often enough that Discord restarting twice in between is unlikely
    timers.discord-call-logs = {
      Unit.Description = "Keep Discord's logs of calls every 5 minutes";
      Timer = {
        OnCalendar = "*:0/5";
        AccuracySec = "1min";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };

  xdg = {
    desktopEntries = {
      # The settings app for this machine's own settings (config/hypr/local.lua)
      machine-settings = {
        name = "Machine Settings";
        comment = "Displays, environment variables and autostart programs of this machine";
        exec = "${config.dotfiles}/config/quickshell/menus/toggle.sh settings";
        # Adwaita's own: the theme Qt reads (the Nix one, first in
        # XDG_DATA_DIRS) doesn't inherit AdwaitaLegacy, which has
        # preferences-desktop-display
        icon = "video-display";
        categories = [ "Settings" ];
      };

      # The scanner window (config/quickshell/menus/scan.qml)
      scanner = {
        name = "Scanner";
        comment = "Scan documents and photos from network scanners into PDFs or images";
        exec = "${config.dotfiles}/config/quickshell/menus/toggle.sh scan";
        icon = "scanner";
        categories = [
          "Graphics"
          "Scanning"
        ];
      };

      # Epson's scanner driver (epsonscan2, AUR) comes with its own scan app:
      # out of the launcher, the scanner window only uses the driver. Same id
      # as the package's entry; ~/.nix-profile comes before /usr in
      # XDG_DATA_DIRS, so this one wins.
      epsonscan2 = {
        name = "Epson Scan 2";
        exec = "epsonscan2";
        noDisplay = true;
      };

      # Pear Desktop (Nix) as "YouTube Music", like its window title: the
      # launcher, the sound menu and the window details take the name from
      # here. Same id as the package's entry; ~/.nix-profile comes before /usr
      # in XDG_DATA_DIRS, so this one wins.
      "com.github.th-ch.youtube-music" = {
        name = "YouTube Music";
        comment = "YouTube Music Desktop App - including custom plugins";
        exec = "pear-desktop";
        icon = "pear-desktop";
        categories = [ "AudioVideo" ];
        settings.StartupWMClass = "com.github.th-ch.youtube-music";
      };
    };

    dataFile = {
      # "Send to <phone> via KDE Connect" in Nautilus' context menu, from the
      # KDE Connect package (Nautilus runs it with nautilus-python from pacman)
      "nautilus-python/extensions/kdeconnect-share.py".source =
        "${config.services.kdeconnect.package}/share/nautilus-python/extensions/kdeconnect-share.py";

      # The lock screen's cover until there is one (config/hypr/hyprlock.conf)
      "lock-media/blank.png".source = pkgs.runCommand "lock-media-blank.png" { } ''
        ${my-pkgs.lock-media}/bin/lock-media blank > $out
      '';

      # For the launcher's emoji search (config/quickshell/menus/Launcher.qml)
      "quickshell-launcher/emoji.json".source = my-pkgs.quickshell-emoji;

      # Same file name as dunst's, so it takes precedence over /usr/share
      "dbus-1/services/org.knopwob.dunst.service".text = ''
        [D-BUS Service]
        Name=org.freedesktop.Notifications
        Exec=/bin/false
        SystemdService=quickshell-daemon.service
      '';

      # Nautilus started over D-Bus (by the portal, when a Flatpak starts it
      # first) is the nautilus service, with its preload
      "dbus-1/services/org.gnome.Nautilus.service".text = ''
        [D-BUS Service]
        Name=org.gnome.Nautilus
        Exec=/bin/false
        SystemdService=nautilus.service
      '';
    };
    # Mask dunst's own unit in case anything asks for it directly
    configFile."systemd/user/dunst.service".source = config.lib.file.mkOutOfStoreSymlink "/dev/null";
    # The SSH agent of gcr (with gnome-keyring, system/packages/session.txt),
    # enabled like `systemctl --user enable` does. It keeps the keys that ssh
    # adds (AddKeysToAgent, home-manager/headless) for the session; the socket
    # sets SSH_AUTH_SOCK for the systemd services itself.
    configFile."systemd/user/sockets.target.wants/gcr-ssh-agent.socket".source =
      config.lib.file.mkOutOfStoreSymlink "/usr/lib/systemd/user/gcr-ssh-agent.socket";
  };

  fonts.fontconfig.enable = true;

  home = {
    # gcr's SSH agent (xdg.configFile above) for the shells
    sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/gcr/ssh";

    # The profile's hicolor theme is put together from the packages' icons and
    # has no icon-theme.cache, so Qt stats every size directory for each icon it
    # looks up there: a name that no theme has took ~0.5 s each (the sound menu
    # tries several per app). Built here like NixOS does for its system profile.
    extraProfileCommands = ''
      if [ -w $out/share/icons/hicolor ]; then
        ${pkgs.gtk3.out}/bin/gtk-update-icon-cache --quiet --ignore-theme-index $out/share/icons/hicolor
      fi
    '';

    # Packages needed on Hyprland specifically, in addition to a standard desktop
    packages = with pkgs; [
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
      grim # screenshots (config/quickshell/menus/screenshot.py)
      wf-recorder # and screen recordings
      qrencode # Wi-Fi QR codes (config/quickshell/menus/network.qml)
      imagemagick
      # The text and QR codes of the screenshot editor and the text of the
      # scanner's PDFs; zbar without its camera apps
      (tesseract.override {
        enableLanguages = [
          "eng"
          "deu"
        ];
      })
      (zbar.override {
        enableVideo = false;
        withXorg = false;
      })
      libnotify
      libsecret
      cliphist
      pavucontrol

      my-pkgs.stay-awake # keeps the screen awake for Sunshine streams (config/sunshine)
      my-pkgs.sunshine-disconnect # ends the Sunshine stream (config/quickshell/menus/power.qml)
      my-pkgs.after-unlock # autostarts that need the keyring (config/hypr/autostart.lua)
      my-pkgs.lock-screen # hyprlock, with the on-screen keyboard in the touch mode
      my-pkgs.lock-media # the media player on the lock screen
      my-pkgs.lock-lockout # the lock screen's time left after too many wrong passwords
      my-pkgs.laptop-idle # dims and suspends laptops when idle (config/hypr/hypridle.conf)
      my-pkgs.quickshell-calendar-python
      my-pkgs.init-tex
      my-pkgs.edit-tex
      my-pkgs.pkg-sync # installed software against the lists and flatpak.nix

      # Apps that aren't on Flathub, instead of the AUR; none needs the GPU
      # much (Nix apps on Arch don't get the NVIDIA driver)
      claude-code
      naps2 # scanning
      tinymediamanager
      pear-desktop # YouTube Music (Electron: software rendering)
      my-pkgs.phones-in-files # the phones in Files' sidebar (config/quickshell/menus/kdeconnect.py)

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
  };
}
