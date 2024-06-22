{ config, ... }:
{
  xdg.configFile."hypr".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/hypr";
  xdg.configFile."waybar".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/waybar";
  xdg.configFile."kitty".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/kitty";
}

