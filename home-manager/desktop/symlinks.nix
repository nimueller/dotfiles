{ config, ... }:
{
  xdg.configFile."hypr".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/hypr";
  xdg.configFile."waybar".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/waybar";
  xdg.configFile."kitty".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/kitty";
  xdg.configFile."brave-flags.conf".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/brave-flags.conf";
  xdg.configFile."rofi".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/rofi";
  xdg.configFile."swayosd".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/swayosd";
}

