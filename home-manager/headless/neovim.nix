{ config, pkgs, inputs, ... }:
{
    nixpkgs.overlays = [
        inputs.neovim-nightly-overlay.overlay
    ];

    programs.neovim.enable = true;

    xdg.configFile."nvim/init.lua".source = ../../config/nvim/init.lua;
    xdg.configFile."nvim/lua".source = ../../config/nvim/lua;

    home.packages = with pkgs; [
        # neovim plugin package dependencies
        ripgrep

        ## language servers
        # Lua
        lua-language-server
        # Nix
        # nixd
        nil
        statix

        # Kotlin/Java
        jdt-language-server
        kotlin-language-server
        ktlint

        # LaTeX
        texliveFull
        evince
        texlab
        ltex-ls

        # JavaScript/TypeScript
        biome
        nodePackages.vscode-langservers-extracted
        nodePackages.eslint
        nodePackages.typescript-language-server
        # Bash
        nodePackages.bash-language-server
    ];
}
