{ pkgs, ... }:
let
    theme = {
        btop = pkgs.fetchFromGitHub {
            owner = "catppuccin";
            repo = "btop";
            rev = "1.0.0";
            sha256 = "J3UezOQMDdxpflGax0rGBF/XMiKqdqZXuX4KMVGTxFk=";
        };

        bat = pkgs.fetchFromGitHub {
            owner = "catppuccin";
            repo = "bat";
            rev = "ba4d16880d63e656acced2b7d4e034e4a93f74b1";
            sha256 = "6WVKQErGdaqb++oaXnY3i6/GuH2FhTgK0v4TN4Y0Wbw=";
        };
    };
in
{
    # Neovim
    # programs.neovim.extraLuaConfig = "vim.cmd.colorscheme \"catppuccin-macchiato\"";

    # btop++
    xdg.configFile."btop/themes/".source = "${theme.btop}/themes/";
    programs.btop.settings.color_theme = "catppuccin_macchiato";

    # Bat
    xdg.configFile."bat/themes/Catppuccin-macchiato.tmTheme".source = "${theme.bat}/Catppuccin-macchiato.tmTheme";
    home.sessionVariables.BAT_THEME = "Catppuccin-macchiato";
}
