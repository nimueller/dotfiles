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

  services.kdeconnect.enable = true;

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
    hyprpaper
    hyprpicker
    grim
    slurp
    libnotify
    libsecret
    inotify-tools
    # waybar
    wtype
    xdotool
    cliphist
    wleave
    pavucontrol

    my-pkgs.hyprshot
    my-pkgs.recorder
    my-pkgs.applauncher
    my-pkgs.init-tex
    my-pkgs.edit-tex

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
    wl-clipboard
    wf-recorder
  ];
}
