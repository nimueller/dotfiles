{ dotfilesLink, ... }:
{
  home.file.".ideavimrc".source = dotfilesLink "config/ideavimrc";
  xdg.configFile."nvim".source = dotfilesLink "config/nvim";
  xdg.configFile."mimeapps.list" = {
    source = dotfilesLink "config/mimeapps.list";
    force = true;
  };
}
