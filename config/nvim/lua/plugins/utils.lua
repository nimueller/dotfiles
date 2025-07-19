return {
  -- Measure VIM startup time
  {
    "dstein64/vim-startuptime",
    -- lazy-load on a command
    cmd = "StartupTime",
    -- init is called during startup. Configuration for vim plugins typically should be set in an init function
    init = function()
      vim.g.startuptime_tries = 10
    end,
  },

  -- Highlight unique jumps for the f and F motions
  -- 'unblevable/quick-scope',

  -- Write files with sudo
  {
    'lambdalisue/vim-suda',
    cmd = "SudaWrite",
  },

  -- Some Neovim improvements and enhancements
  { 'echasnovski/mini.nvim', version = '*' },
}

-- vim: ts=2 sts=2 sw=2 et
