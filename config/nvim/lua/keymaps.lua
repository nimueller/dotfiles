-- Non VIM keymaps because I'm used to them...
vim.keymap.set({ 'n', 'v', 'i' }, '<C-A>', '<ESC>gg0vG$')

-- Remap for dealing with word wrap
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

-- Bufferline maps to switch tabs
vim.keymap.set({ 'n', 'v', 'i' }, '<A-Left>', '<ESC>:BufferLineCyclePrev<CR>', { silent = true })
vim.keymap.set({ 'n', 'v', 'i' }, '<A-Right>', '<ESC>:BufferLineCycleNext<CR>', { silent = true })
vim.keymap.set({ 'n', 'v', 'i' }, '<A-S-Left>', '<ESC>:BufferLineMovePrev<CR>', { silent = true })
vim.keymap.set({ 'n', 'v', 'i' }, '<A-S-Right>', '<ESC>:BufferLineMoveNext<CR>', { silent = true })

-- Telescope
vim.keymap.set('n', '<leader>ff', ':Telescope find_files<CR>', { silent = true, desc = '[F]ind [F]ile' })
vim.keymap.set('n', '<leader>fw', ':Telescope grep_string<CR>', { silent = true, desc = '[F]ind [W]ord under cursor' })
vim.keymap.set('n', '<leader>fg', ':Telescope live_grep<CR>', { silent = true, desc = '[F]ind matches using [G]rep' })
vim.keymap.set('n', '<leader>fr', ':Telescope resume<CR>', { silent = true, desc = '[F]ind [R]esume' })
vim.keymap.set('n', '<leader>fp', ':Telescope pickers<CR>', { silent = true, desc = '[F]ind [P]revious' })
vim.keymap.set('n', '<A-CR>', ':Telescope spell_suggest<CR>', { silent = true })

-- vim: ts=2 sts=2 sw=2 et
