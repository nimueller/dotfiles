-- LSP servers
local servers = {
	lua_ls = {
		Lua = {
			workspace = { checkThirdParty = false },
			telemetry = { enable = false },
		},
	},
	nil_ls = {
		["nil"] = {
			formatting = {
				command = { "nixpkgs-fmt" },
			},
			nix = {
				maxMemoryMB = 4096,
				flake = {
					autoArchive = true,
				},
			},
		},
	},
	statix = {},
	biome = {},

	eslint = {},
	tsserver = {},
	prismals = {},
	jsonls = {},

	docker_compose_language_service = {},

	cssls = {},
	bashls = {},
	texlab = {},
	ltex = {},

	lemminx = {},
	jdtls = {},
	kotlin_language_server = {},
}

local augroup = vim.api.nvim_create_augroup("LspFormatting", {})

local on_attach = function(client, bufnr)
	local nmap = function(keys, func, desc)
		if desc then
			desc = "LSP: " .. desc
		end

		vim.keymap.set("n", keys, func, { buffer = bufnr, desc = desc })
	end

	nmap("<leader>ca", vim.lsp.buf.code_action, "[C]ode [A]ction")
	nmap("<leader>cf", vim.lsp.buf.format, "[C]ode [F]ormat")
	nmap("<leader>cr", vim.lsp.buf.rename, "[C]ode [R]ename")

	nmap("<leader>ds", require("telescope.builtin").lsp_document_symbols, "[D]ocument [S]ymbols")
	nmap("<leader>ws", require("telescope.builtin").lsp_dynamic_workspace_symbols, "[W]orkspace [S]ymbols")

	-- See `:help K` for why this keymap
	nmap("K", vim.lsp.buf.hover, "Hover Documentation")
	nmap("<C-p>", vim.lsp.buf.signature_help, "Signature Documentation")

	-- Lesser used LSP functionality
	nmap("gd", vim.lsp.buf.definition, "[G]oto [D]efinition")
	nmap("gD", vim.lsp.buf.declaration, "[G]oto [D]eclaration")
	nmap("<leader>wa", vim.lsp.buf.add_workspace_folder, "[W]orkspace [A]dd Folder")
	nmap("<leader>wr", vim.lsp.buf.remove_workspace_folder, "[W]orkspace [R]emove Folder")
	nmap("<leader>wl", function()
		print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
	end, "[W]orkspace [L]ist Folders")

	if client.supports_method("textDocument/formatting") then
		vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
		vim.api.nvim_create_autocmd("BufWritePre", {
			group = augroup,
			buffer = bufnr,
			callback = function()
				vim.lsp.buf.format({ bufnr = bufnr })
			end,
		})
	end

	for key, value in pairs(client) do
		if key == "name" and value == "ltex" then
			print("setting up ltex extra")
			require("ltex_extra").setup({
				path = ".ltex",
			})
		end
	end
end

-- Setup neovim lua configuration
require("neodev").setup()

local lsp = require("lspconfig")

for server_name, config in pairs(servers) do
	lsp[server_name].setup({
		on_attach = on_attach,
		settings = config,
	})
end

local null_ls = require("null-ls")
null_ls.setup({
	sources = {
		null_ls.builtins.diagnostics.luacheck,
		null_ls.builtins.diagnostics.tidy,
		null_ls.builtins.diagnostics.ktlint,
		null_ls.builtins.formatting.stylua,
		null_ls.builtins.formatting.ktlint,
		null_ls.builtins.formatting.tidy,
	},
})

local telescope = require("telescope")
telescope.load_extension("ui-select")
