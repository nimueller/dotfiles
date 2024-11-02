{ config, ... }:
{
  home.file.".zshrc".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/zshrc";
  home.file.".tmux.conf".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/tmux.conf";
  xdg.configFile."mimeapps.list".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/mimeapps.list";
  xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/nvim";
}
