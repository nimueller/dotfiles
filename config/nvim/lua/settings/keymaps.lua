-- Non VIM-ish keymaps because I'm used to them...
vim.keymap.set({ 'n', 'v', 'i' }, '<C-a>', '<ESC>gg0vG$')
vim.keymap.set('v', '<C-c>', '"+y')
vim.keymap.set({ 'n', 'v', 'i' }, '<C-v>', '"+p')

-- Clear highlighting after search
vim.keymap.set('n', '<ESC>', ':nohlsearch<CR>', { silent = true })

-- Remap for dealing with word wrap
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

-- Move entire lines when in visual mode
vim.keymap.set('v', 'K', ":m '<-2<CR>gv=gv", { silent = true })
vim.keymap.set('v', 'J', ":m '<+1<CR>gv=gv", { silent = true })

-- Cursor jump fixes when scrolling or searching
vim.keymap.set('n', '<C-d>', '<C-d>zz')
vim.keymap.set('n', '<C-u>', '<C-u>zz')
vim.keymap.set('n', 'n', 'nzz')
vim.keymap.set('n', 'N', 'Nzz')

-- Paste without overwriting the register with the replaced text
vim.keymap.set('x', '<leader>p', '"_dP')

-- Who needs this anyway?
vim.keymap.set('n', 'Q', '<Nop>')

-- Bufferline maps to switch tabs
vim.keymap.set({ 'n', 'v', 'i' }, '<A-Left>', '<ESC>:BufferLineCyclePrev<CR>', { silent = true })
vim.keymap.set({ 'n', 'v', 'i' }, '<A-Right>', '<ESC>:BufferLineCycleNext<CR>', { silent = true })
vim.keymap.set({ 'n', 'v' }, '<S-H>', '<ESC>:BufferLineCyclePrev<CR>', { silent = true })
vim.keymap.set({ 'n', 'v' }, '<S-L>', '<ESC>:BufferLineCycleNext<CR>', { silent = true })
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
