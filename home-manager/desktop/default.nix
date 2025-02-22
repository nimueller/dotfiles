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

  xdg.configFile."nwg-bar/style.css".source = ../../config/nwg-bar/style.css;
  xdg.configFile."nwg-bar/bar.json".text =
    builtins.replaceStrings
      [ "$nwg_install_path" ]
      [ "${pkgs.nwg-bar}" ]
      (builtins.readFile ../../config/nwg-bar/bar.json);

  dconf.settings = {
    "com/github/stunkymonkey/nautilus-open-any-terminal" = {
      terminal = "kitty";
    };
  };

  # Dunst as notification daemon
  services.dunst = {
    enable = true;

    settings = {
      global = {
        follow = "mouse";
        idle_threshold = "1m";
        format = "<b>%s</b>\\n%b\\n%p";
        vertical_alignment = "top";
      };
    };
  };

  xdg.configFile."rofi".source = ../../config/rofi;
  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
    plugins = [
      pkgs.rofi-calc
    ];
  };

  services.kdeconnect.enable = true;

  fonts.fontconfig.enable = true;

  # Packages needed on Hyprland specifically, in addition to a standard desktop
  home.packages = with pkgs; [
    nerd-fonts.noto
    noto-fonts
    noto-fonts-color-emoji

    swayosd

    xdg-terminal-exec
    playerctl
    hyprpaper
    hyprpicker
    grim
    slurp
    libnotify
    libsecret
    inotify-tools
    # waybar
    wtype
    cliphist
    nwg-bar
    pavucontrol

    my-pkgs.hyprshot
    my-pkgs.recorder
    my-pkgs.applauncher

    # Gnome GUI apps
    adwaita-icon-theme
    evince # PDF viewer
    eog # Image viewer
    totem # Video player
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
    webcord
    wl-clipboard
    wf-recorder
  ];
}
