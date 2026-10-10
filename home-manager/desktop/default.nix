{ pkgs, lib, ... }:
let
  my-pkgs = import ../../pkgs { inherit pkgs lib; };
in
{
  nixpkgs.config.allowUnfree = true;
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
    nerd-fonts.monofur
    noto-fonts
    noto-fonts-lgc-plus
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-emoji-blob-bin
    noto-fonts-color-emoji
    noto-fonts-monochrome-emoji

    rofi
    swayosd

    xdg-terminal-exec
    playerctl
    hyprpicker
    grim
    slurp
    libnotify
    libsecret
    inotify-tools
    wtype
    xdotool
    cliphist
    pavucontrol
    quickshell # bar menus and app launcher (config/quickshell/menus)

    my-pkgs.hyprshot
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
    # Gnome Circle GUI apps
    apostrophe # Markdown viewer
    # Other GUI apps
    keepassxc
    wl-clipboard
    wf-recorder
  ];
}
