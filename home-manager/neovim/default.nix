{ config, pkgs, lib, ... }:
{
    programs.neovim = {
        enable = true;
        defaultEditor = true;
        viAlias = true;
        vimAlias = true;

        extraConfig = builtins.readFile ./vimrc;
        extraLuaConfig = builtins.readFile ./neovim.lua;

        plugins = with pkgs.vimPlugins; [
            # Theme
            tokyonight-nvim
            
            # Explorer (VIM Tree)
            nui-nvim
            plenary-nvim
            neo-tree-nvim
            nvim-web-devicons

            # Treesitter
            nvim-treesitter.withAllGrammars

            # UI
            nvim-notify
            nvim-lsp-notify
            dressing-nvim
            lualine-nvim
            bufferline-nvim
            noice-nvim

            # LSPs
            nvim-lspconfig

            # Completions and suggestions
            nvim-cmp
            cmp-nvim-lsp
            cmp-path
            cmp_luasnip

            comment-nvim
            vim-illuminate
            which-key-nvim
            vim-startuptime
        ];
    };

    home.packages = with pkgs; [
        # Nix LSP
        nixd
        vscode-langservers-extracted
    ];
}
