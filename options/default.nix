{ config, lib, ... }: {
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
}
