{ config, pkgs, lib, inputs, ... }:
let
  my-pkgs = import ../../pkgs { inherit pkgs lib; };
in
{
  nixpkgs.config.allowUnfree = true;

  imports = [
    # inputs.hyprland.homeManagerModules.default
    inputs.spicetify-nix.homeManagerModule
    # ./apps.nix
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

  # Use kitty as terminal emulator
  # programs.kitty = {
  #   enable = true;
  #   settings = {
  #     font_family = "Jet Brains Mono";
  #     show_hyperlink_targets = true;
  #     copy_on_select = "clipboard";
  #     strip_trailing_spaces = "smart";
  #     focus_follows_mouse = true;
  #     shell = "tmux";
  #   };
  #   keybindings = {
  #     "ctrl+v" = "paste_from_clipboard";
  #   };
  # };

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
    qt5.qtwayland
    qt6.qtwayland
    gtk3
    gtk4

    swayosd
    udiskie

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
    # gnome.totem # Video player
    gnome.gnome-characters # Emoji picker
    gnome.gnome-font-viewer
    gnome.dconf-editor
    gnome.file-roller
    gnome.seahorse # Manage keyring
    gnome.geary
    # Gnome Circle GUI apps
    apostrophe # Markdown viewer
    # Other GUI apps
    keepassxc
    webcord
    wl-clipboard
    wf-recorder
    jetbrains.idea-ultimate
  ];
}
