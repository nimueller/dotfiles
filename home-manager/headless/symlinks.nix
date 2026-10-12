{ config, ... }:
{
  home.file.".ideavimrc".source =
    config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/ideavimrc";
  xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/nvim";
  xdg.configFile."mimeapps.list" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/mimeapps.list";
    force = true;
  };
}
