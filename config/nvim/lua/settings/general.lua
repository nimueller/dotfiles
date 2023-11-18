-- Enable mouse mode
vim.o.mouse = 'a'

-- Enable line numbers and relative line numbers
vim.wo.number = true
vim.wo.relativenumber = true

-- Always show 10 lines below or above the cursor
vim.o.scrolloff = 10

-- Line break column
vim.o.colorcolumn = '120'

-- Enable break indent
vim.o.breakindent = true

-- Save undo history
vim.o.swapfile = false
vim.o.backup = false
vim.o.undodir = os.getenv('HOME') .. '/.vim/undodir'
vim.o.undofile = true

-- Search settings
vim.o.hlsearch = true
vim.o.incsearch = true
vim.o.ignorecase = true
vim.o.smartcase = true

-- Keep signcolumn on by default
vim.wo.signcolumn = 'yes'

-- Decrease update time
vim.o.updatetime = 250
vim.o.timeoutlen = 300

-- Set completeopt to have a better completion experience
vim.o.completeopt = 'menuone,noselect'

-- NOTE: You should make sure your terminal supports this
vim.o.termguicolors = true
