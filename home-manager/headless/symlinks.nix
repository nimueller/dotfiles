{ config, ... }:
{
  home.file.".zshrc".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/zshrc";
  home.file.".tmux.conf".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/tmux.conf";
  xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/config/nvim";
}
