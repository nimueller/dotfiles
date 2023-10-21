vim.opt.termguicolors = true

vim.keymap.set('n', '<Leader>e', ':Neotree focus<CR>')

require 'notify'.setup()
require 'dressing'.setup()
local bufferline = require 'bufferline'
bufferline.setup {
    options = {
        style_preset = bufferline.style_preset.slant,
        middle_mouse_command = "bdelete! %d",
        right_mouse_command = "vertical sbuffer %d",
        diagnostics = "nvim_lsp",
        diagnostics_indicator = function(count, level, diagnostics_dict, context)
          local icon = level:match("error") and " " or " "
          return " " .. icon .. count
        end,
        offsets = {
            {
                filetype = "neo-tree",
                text = "Neo-tree",
                highlight = "Directory",
                text_align = "left",
            }
        },
    },
}
vim.keymap.set('n', '<A-Left>', ':BufferLineCyclePrev<CR>')
vim.keymap.set('n', '<A-Right>', ':BufferLineCycleNext<CR>')
vim.keymap.set('n', '<A-S-Left>', ':BufferLineMovePrev<CR>')
vim.keymap.set('n', '<A-S-Right>', ':BufferLineMoveNext<CR>')

require 'lualine'.setup {
    options = {
        ignore_focus = { "neo-tree" },
        globalstatus = true,
    },
}

require 'Comment'.setup()

local cmp = require 'cmp'
cmp.setup {
    snippet = {
        expand = function(args)
            require('luasnip').lsp_expand(args.body)
        end,
    },
    completion = {
      completeopt = "menu,menuone,noinsert",
    },
    mapping = cmp.mapping.preset.insert({
      ["<C-n>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
      ["<C-p>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
      ["<C-b>"] = cmp.mapping.scroll_docs(-4),
      ["<C-f>"] = cmp.mapping.scroll_docs(4),
      ["<C-Space>"] = cmp.mapping.complete(),
      ["<C-e>"] = cmp.mapping.abort(),
      ["<CR>"] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
      ["<TAB>"] = cmp.mapping.confirm({ behavior = cmp.ConfirmBehavior.Replace, select = true, }), -- Replace with currentyl selected item.
      ["<C-CR>"] = function(fallback)
        cmp.abort()
        fallback()
      end,
    }),
    sources = cmp.config.sources({
      { name = "nvim_lsp" },
      { name = "luasnip" },
      { name = "path" },
    }, {
      { name = "buffer" },
    }),
}

require 'which-key'


local lspconfig = require 'lspconfig'
lspconfig.nixd.setup {}
lspconfig.jsonls.setup {}
lspconfig.bashls.setup {}

require 'noice'.setup {
    lsp = {
        -- override markdown rendering so that **cmp** and other plugins use **Treesitter**
        override = {
            ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
            ["vim.lsp.util.stylize_markdown"] = true,
            ["cmp.entry.get_documentation"] = true,
        },
    },
    -- you can enable a preset for easier configuration
    presets = {
        bottom_search = true, -- use a classic bottom cmdline for search
        command_palette = true, -- position the cmdline and popupmenu together
        long_message_to_split = true, -- long messages will be sent to a split
        inc_rename = false, -- enables an input dialog for inc-rename.nvim
        lsp_doc_border = false, -- add a border to hover docs and signature help
    },
}


