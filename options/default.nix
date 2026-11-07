{ config, lib, ... }:
{
  options = {
    dotfiles = lib.mkOption {
      type = lib.types.path;
      apply = toString;
      default = "${config.home.homeDirectory}/dotfiles";
      example = "${config.home.homeDirectory}/dotfiles";
      description = "Location of the dotfiles working copy";
    };

    devTools = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = "Install the language servers, formatters and toolchains of home-manager/dev (several GB)";
    };
  };

  # `dotfilesLink "config/kitty"`: a link into the working copy instead of a
  # copy in the Nix store, so a change there applies without a switch
  config._module.args.dotfilesLink =
    path: config.lib.file.mkOutOfStoreSymlink "${config.dotfiles}/${path}";
}
