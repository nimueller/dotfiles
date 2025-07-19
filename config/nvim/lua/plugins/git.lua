return {
	-- Git commands inside Neovim
	{
		"tpope/vim-fugitive",
		cmd = "Git",
	},

	-- Adds git related signs to the gutter, as well as utilities for managing changes
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPost", "BufNewFile" },
		opts = {
			signs = {
				add = { text = "+" },
				change = { text = "~" },
				delete = { text = "_" },
				topdelete = { text = "‾" },
				changedelete = { text = "~" },
			},
			current_line_blame_opts = {
				virt_text_pos = "eol", -- 'eol' | 'overlay' | 'right_align'
				delay = 0,
			},
			on_attach = function(bufnr)
				vim.keymap.set(
					"n",
					"<leader>gh",
					"<cmd>Gitsigns preview_hunk<cr>",
					{ buffer = bufnr, desc = "[G]it [H]unk", silent = true }
				)
				vim.keymap.set(
					"n",
					"<leader>gb",
					"<cmd>Gitsigns toggle_current_line_blame<cr>",
					{ buffer = bufnr, desc = "[G]it [B]lame", silent = true }
				)

				-- don't override the built-in and fugitive keymaps
				local gs = package.loaded.gitsigns
				vim.keymap.set({ "n", "v" }, "]c", function()
					if vim.wo.diff then
						return "]c"
					end
					vim.schedule(function()
						gs.next_hunk()
					end)
					return "<Ignore>"
				end, { expr = true, buffer = bufnr, desc = "Jump to next hunk" })
				vim.keymap.set({ "n", "v" }, "[c", function()
					if vim.wo.diff then
						return "[c"
					end
					vim.schedule(function()
						gs.prev_hunk()
					end)
					return "<Ignore>"
				end, { expr = true, buffer = bufnr, desc = "Jump to previous hunk" })
			end,
		},
	},
}
