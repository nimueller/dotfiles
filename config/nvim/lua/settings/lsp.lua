-- LSP servers
local servers = {
  lua_ls = {
    Lua = {
      workspace = { checkThirdParty = false },
      telemetry = { enable = false },
    },
  },
  nil_ls = {},
  statix = {},
  biome = {},
  tsserver = {},
  jsonls = {},
  cssls = {},
  eslint = {},
  bashls = {},
  texlab = {},
  ltex = {},
  jdtls = {},
  kotlin_language_server = {}
}

local on_attach = function(_, bufnr)
  local nmap = function(keys, func, desc)
    if desc then
      desc = 'LSP: ' .. desc
    end

    vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
  end

  nmap('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')
  nmap('<leader>cf', vim.lsp.buf.format, '[C]ode [F]ormat')
  nmap('<leader>cr', vim.lsp.buf.rename, '[C]ode [R]ename')

  nmap('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
  nmap('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

  -- See `:help K` for why this keymap
  nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
  nmap('<C-p>', vim.lsp.buf.signature_help, 'Signature Documentation')

  -- Lesser used LSP functionality
  nmap('gd', vim.lsp.buf.definition, '[G]oto [D]efinition')
  nmap('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
  nmap('<leader>wa', vim.lsp.buf.add_workspace_folder, '[W]orkspace [A]dd Folder')
  nmap('<leader>wr', vim.lsp.buf.remove_workspace_folder, '[W]orkspace [R]emove Folder')
  nmap('<leader>wl', function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, '[W]orkspace [L]ist Folders')

  -- Create a command `:Format` local to the LSP buffer
  vim.api.nvim_buf_create_user_command(bufnr, 'Format', function(_)
    vim.lsp.buf.format()
  end, { desc = 'Format current buffer with LSP' })
end

-- Setup neovim lua configuration
require('neodev').setup()

local lsp = require 'lspconfig'

for server_name, config in pairs(servers) do
  lsp[server_name].setup {
    on_attach = on_attach,
    settings = config,
  }
end

local null_ls = require'null-ls'
null_ls.setup({
  sources = {
    null_ls.builtins.diagnostics.ktlint,
    null_ls.builtins.formatting.ktlint
  }
})
