---Creates a keymap for the given mode, keys, and function.
---@param mode string
---@param key string
---@param keymap function | string
---@param description string | nil
---@return nil
local function map(mode, key, keymap, description)
	if mode == nil then error("Mode for '" .. key .. "' is nil!") end
	if keymap == nil then error("Keymap for '" .. key .. "' is nil!") end

	vim.keymap.set(mode, key, keymap, {
		desc = description
	})
end

---Creates a keymap for normal mode.
---@param key string
---@param keymap function | string
---@param description string | nil
---@return nil
local function nmap(key, keymap, description) map("n", key, keymap, description) end

---Creates a keymap for insert mode.
---@param keys string
---@param func function | string
---@param desc string | nil
---@return nil
local function imap(keys, func, desc) map("i", keys, func, desc) end


-- Non VIM-ish keymaps because I'm used to them...
vim.keymap.set({ 'n', 'v' }, '<leader>a', '<ESC>gg0vG$')
vim.keymap.set('v', '<C-c>', '"+y')
vim.keymap.set({ 'n', 'v', 'i' }, '<C-v>', '<ESC>"+p')

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

-- Switch between windows
nmap('<S-h>', '<C-w>h')
nmap('<S-j>', '<C-w>j')
nmap('<S-k>', '<C-w>k')
nmap('<S-l>', '<C-w>l')

-- Diagnostics
nmap("<leader>e", vim.diagnostic.open_float, "Open floating diagnostic message")
nmap("<leader>q", vim.diagnostic.setloclist, "Open diagnostics list")

-- LSP
vim.api.nvim_create_autocmd('LspAttach', {
	callback = function(ev)
		local client = assert(vim.lsp.get_client_by_id(ev.data.client_id))

		nmap('<leader>ca', vim.lsp.buf.code_action, "[C]ode [A]ction")
		nmap('<leader>ci', vim.lsp.buf.implementation, "[C]ode [I]mplementation")
		nmap('<leader>cr', vim.lsp.buf.references, "[C]ode [R]eferences")
		nmap('<leader>cs', vim.lsp.buf.document_symbol, "[C]ode [S]ymbols")
		nmap('<leader>cd', vim.lsp.buf.definition, "[C]ode [D]efinition")
		nmap('<leader>ct', vim.lsp.buf.type_definition, "[C]ode [T]ype Definition")
		nmap('<leader>cr', vim.lsp.buf.rename, "[C]ode [R]ename")
		nmap('<leader>cf', function() vim.lsp.buf.format({ async = false }) end, "[C]ode [F]ormat")
		nmap('K', vim.lsp.buf.hover, "Code Hover")
		nmap('gK', vim.lsp.buf.declaration, "Code Declaration")


		vim.keymap.set({ 'n', 'i' }, "<C-p>", vim.lsp.buf.signature_help, { desc = "Signature Documentation" })

		nmap("<leader>wa", vim.lsp.buf.add_workspace_folder, "[W]orkspace [A]dd Folder")
		nmap("<leader>wr", vim.lsp.buf.remove_workspace_folder, "[W]orkspace [R]emove Folder")
	end
})
