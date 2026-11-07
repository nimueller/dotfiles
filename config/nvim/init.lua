-- Set <space> as the leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- lazy.nvim installs itself on the first start
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", -- latest stable release
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

-- The plugins, one module per area in lua/plugins
require("lazy").setup({
    -- The colour scheme first, before anything that draws
    {
        "catppuccin/nvim",
        name = "catppuccin",
        priority = 1000,
        lazy = false,
        config = function()
            vim.cmd([[colorscheme catppuccin-macchiato]])
        end,
    },

    require("plugins.editor"),
    require("plugins.git"),
    require("plugins.lsp"),
    require("plugins.ui"),
    require("plugins.utils"),
}, {})

vim.keymap.set({ "n", "v" }, "<Space>", "<Nop>", { silent = true })

-- Highlight what was yanked
local highlight_group = vim.api.nvim_create_augroup("YankHighlight", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
    callback = function()
        vim.hl.on_yank()
    end,
    group = highlight_group,
    pattern = "*",
})

require("settings/general")
require("settings/keymaps")
