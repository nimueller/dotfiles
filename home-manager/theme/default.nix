{ pkgs, ... }:
let
  theme = {
    btop = pkgs.fetchFromGitHub {
      owner = "catppuccin";
      repo = "btop";
      rev = "1.0.0";
      sha256 = "J3UezOQMDdxpflGax0rGBF/XMiKqdqZXuX4KMVGTxFk=";
    };
  };
in
{
  # btop++
  xdg.configFile."btop/themes/".source = "${theme.btop}/themes/";

  programs = {
    btop.settings.color_theme = "catppuccin_macchiato";

    # bat ships the Catppuccin themes itself
    bat = {
      enable = true;
      config.theme = "Catppuccin Macchiato";
    };
    # delta has the same themes built in
    delta.options.syntax-theme = "Catppuccin Macchiato";
  };
}
