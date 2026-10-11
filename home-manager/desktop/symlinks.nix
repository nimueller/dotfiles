{ config, ... }:
{
  xdg.configFile = {
    "hypr".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/hypr";
    "kitty".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/kitty";
    "brave-flags.conf".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/brave-flags.conf";
    "quickshell".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/quickshell";
  };
}
