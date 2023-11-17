-- Non VIM keymaps because I'm used to them...
vim.keymap.set({ 'n', 'v', 'i' }, '<C-A>', '<ESC>gg0vG$')

-- Remap for dealing with word wrap
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

-- BufferLine maps to switch tabs
vim.keymap.set('n', '<A-Left>', ':BufferLineCyclePrev<CR>', { silent = true })
vim.keymap.set('n', '<A-Right>', ':BufferLineCycleNext<CR>', { silent = true })
vim.keymap.set('n', '<A-S-Left>', ':BufferLineMovePrev<CR>', { silent = true })
vim.keymap.set('n', '<A-S-Right>', ':BufferLineMoveNext<CR>', { silent = true })

-- Telescope
vim.keymap.set('n', '<leader>ff', ':Telescope find_files<CR>', { silent = true, desc = '[F]ind [F]ile' })
vim.keymap.set('n', '<leader>fw', ':Telescope grep_string<CR>', { silent = true, desc = '[F]ind [W]ord under cursor' })
vim.keymap.set('n', '<leader>fg', ':Telescope grep_string<CR>', { silent = true, desc = '[F]ind matches using [G]rep' })
vim.keymap.set('n', '<leader>fr', ':Telescope resume<CR>', { silent = true, desc = '[F]ind [R]esume' })
vim.keymap.set('n', '<leader>fp', ':Telescope pickers<CR>', { silent = true, desc = '[F]ind [P]revious' })
vim.keymap.set('n', '<A-CR>', ':Telescope spell_suggest<CR>', { silent = true })

-- vim: ts=2 sts=2 sw=2 et
