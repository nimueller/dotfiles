{ config, pkgs, lib, inputs, ... }:
let
  my-pkgs = import ../../pkgs { inherit pkgs lib; };
in
{
  nixpkgs.config.allowUnfree = true;

  imports = [
    inputs.hyprland.homeManagerModules.default
    inputs.spicetify-nix.homeManagerModule
    ./apps.nix
    ./gaming.nix
    ../theme/desktop.nix
  ];

  # Basic Hyprland configuration
  wayland.windowManager.hyprland = {
    enable = true;
    extraConfig =
      builtins.readFile ../../config/hypr/general.conf +
      builtins.readFile ../../config/hypr/windowrules.conf +
      builtins.readFile ../../config/hypr/workspacerules.conf +
      builtins.readFile ../../config/hypr/keybinds.conf +
      builtins.readFile ../../config/hypr/autostart.conf;
  };

  xdg.configFile."waybar".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/waybar";

  xdg.configFile."nwg-bar/style.css".source = ../../config/nwg-bar/style.css;
  xdg.configFile."nwg-bar/bar.json".text =
    builtins.replaceStrings
      [ "$nwg_install_path" ]
      [ "${pkgs.nwg-bar}" ]
      (builtins.readFile ../../config/nwg-bar/bar.json);

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      # Terminal
      "application/x-shellscript" = "kitty.desktop";
      "application/x-sh" = "kitty.desktop";
      "application/x-terminal" = "kitty.desktop";
      # Browser
      "text/html" = "brave.desktop";
      "x-scheme-handler/http" = "brave.desktop";
      "x-scheme-handler/https" = "brave.desktop";
      "x-scheme-handler/about" = "brave.desktop";
      "x-scheme-handler/unknown" = "brave.desktop";
      # Text
      "text/plain" = "nvim.desktop";
      "text/markdown" = "org.gnome.gitlab.somas.Apostrophe.desktop";
      # Images
      "image/png" = "org.gnome.eog.desktop";
      "image/jpeg" = "org.gnome.eog.desktop";
      # Other
      "inode/directory" = "org.gnome.Nautilus.desktop";
      "x-scheme-handler/mailspring" = "Mailspring.desktop";
      "application/pdf" = "org.gnome.Evince.desktop";
    };
  };

  dconf.settings = {
    "com/github/stunkymonkey/nautilus-open-any-terminal" = {
      terminal = "kitty";
    };
  };

  # Use kitty as terminal emulator
  programs.kitty = {
    enable = true;
    settings = {
      font_family = "Jet Brains Mono";
      show_hyperlink_targets = true;
      copy_on_select = "clipboard";
      strip_trailing_spaces = "smart";
      focus_follows_mouse = true;
      shell = "tmux";
    };
    keybindings = {
      "ctrl+v" = "paste_from_clipboard";
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

  services.swayosd.enable = true;

  # Auto Mount USB devices
  services.udiskie.enable = true;

  programs.spicetify.enable = true;

  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
    extraConfig = {
      modi = "combi";
      combi-modes = "drun,ssh";
      show-icons = true;
      drun-display-format = "{icon} {name}";
      display-combi = " 󱓞 Launch ";
      display-calc = " 󰃬 Calc ";
      display-drun = " App";
      display-ssh = " 󱘖 SSH";
    };
    plugins = [
      pkgs.rofi-calc
    ];
  };

  services.kdeconnect.enable = true;

  fonts.fontconfig.enable = true;

  # Packages needed on Hyprland specifically, in addition to a standard desktop
  home.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "JetBrainsMono" ]; })

    # Utility
    polkit-kde-agent
    qt5.qtwayland
    qt6.qtwayland
    gtk3
    gtk4

    xdg-terminal-exec
    playerctl
    hyprpaper
    hyprpicker
    grim
    slurp
    libnotify
    libsecret
    inotify-tools
    waybar
    wtype
    cliphist
    nwg-bar
    pavucontrol

    my-pkgs.hyprshot
    my-pkgs.recorder
    my-pkgs.applauncher

    # Gnome GUI apps
    gnome.adwaita-icon-theme
    gnome.evince # PDF viewer
    gnome.eog # Image viewer
    gnome.totem # Video player
    gnome.gnome-characters # Emoji picker
    gnome.gnome-font-viewer
    gnome.dconf-editor
    # Gnome Circle GUI apps
    apostrophe # Markdown viewer
    # Other GUI apps
    gimp
    keepassxc
    brave
    firefox
    webcord
    obs-studio
    wl-clipboard
    wf-recorder
    jetbrains.idea-ultimate
  ];
}
