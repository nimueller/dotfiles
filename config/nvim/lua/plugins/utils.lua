return {
    -- Measure Vim startup time
    {
        "dstein64/vim-startuptime",
        cmd = "StartupTime",
        init = function()
            vim.g.startuptime_tries = 10
        end,
    },

    -- Write files with sudo
    {
        "lambdalisue/vim-suda",
        cmd = "SudaWrite",
    },

    -- Some Neovim improvements and enhancements
    {
        "echasnovski/mini.nvim",
        version = "*",
    },
}
