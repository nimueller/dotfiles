return {
	{
		-- Base LSP plugin for easier LSP setup
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			{ 'williamboman/mason.nvim', config = true },
			'williamboman/mason-lspconfig.nvim',
			'WhoIsSethDaniel/mason-tool-installer.nvim',
		},
		config = function()
			require("lspconfig")
			require("settings.lsp")
		end
	},

	{
		-- lazy.nvim development
		"folke/lazydev.nvim",
		ft = "lua",
		opts = {
			library = {
				{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
			},
		},
	},

	{
		-- Fuzzy Autocompletion
		"saghen/blink.cmp",
		version = "1.*",
		event = "InsertEnter",
		opts = {
			sources = {
				default = { "lazydev", "lsp", "path", "snippets", "buffer" },
				providers = {
					lazydev = {
						name = "LazyDev",
						module = "lazydev.integrations.blink",
						score_offset = 100,
					},
				},
			},
			keymap = {
				preset = "enter"
			}
		},
	},

	{
		"nvimtools/none-ls.nvim",
		event = { "BufReadPre", "BufNewFile" },

		config = function()
			local null_ls = require("null-ls")
			local augroup = vim.api.nvim_create_augroup("LspFormatting", {})

			null_ls.setup({
				sources = {
					null_ls.builtins.diagnostics.deadnix,
					null_ls.builtins.diagnostics.editorconfig_checker,
					null_ls.builtins.diagnostics.tidy,
					null_ls.builtins.diagnostics.ktlint,
					null_ls.builtins.diagnostics.markdownlint2,
					null_ls.builtins.formatting.stylua,
					null_ls.builtins.formatting.ktlint,
					null_ls.builtins.formatting.tidy,
				},
				on_attach = function(_, bufnr)
					vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
					vim.api.nvim_create_autocmd("BufWritePre", {
						group = augroup,
						buffer = bufnr,
						callback = function()
							vim.lsp.buf.format({ async = false })
						end,
					})
				end,
			})
		end,
	}
}
