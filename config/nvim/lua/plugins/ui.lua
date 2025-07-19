return {
	-- Make VIM look nice (entire UI reworked)
	{
		"folke/noice.nvim",
		event = "VeryLazy",
		dependencies = {
			"MunifTanjim/nui.nvim",
		},
		opts = {
			lsp = {
				override = {
					["vim.lsp.util.convert_input_to_markdown_lines"] = true,
					["vim.lsp.util.stylize_markdown"] = true,
					["cmp.entry.get_documentation"] = true,
				},
			},
			presets = {
				bottom_search = false,
				command_palette = true,
				long_message_to_split = true,
				inc_rename = false,
				lsp_doc_border = true,
			},
		},
	},

	-- File explorer
	{
		"nvim-neo-tree/neo-tree.nvim",
		branch = "v3.x",
		keys = {
			{ "<leader>ft", ":Neotree focus<CR>", desc = "[F]ile [T]ree", silent = true },
		},
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-web-devicons",
			"MunifTanjim/nui.nvim",
		},
		opts = {
			sources = { "filesystem", "buffers", "git_status", "document_symbols" },
			open_files_do_not_replace_types = { "terminal", "Trouble", "trouble", "qf", "Outline" },
			filesystem = {
				bind_to_cwd = false,
				follow_current_file = { enabled = true },
				use_libuv_file_watcher = true,
			},
			window = {
				mappings = {
					["<space>"] = "none",
				},
			},
			default_component_configs = {
				indent = {
					with_expanders = true, -- if nil and file nesting is enabled, will enable expanders
					expander_collapsed = "",
					expander_expanded = "",
					expander_highlight = "NeoTreeExpander",
				},
			},
		},
	},

	-- Useful plugin to show you pending keybinds.
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			icons = {
				-- set icon mappings to true if you have a Nerd Font
				mappings = vim.g.have_nerd_font,
			},
			spec = {
				{ "<leader>c", group = "[C]ode" },
				{ "<leader>d", group = "[D]ocument" },
				{ "<leader>f", group = "[F]ile" },
				{ "<leader>g", group = "[G]it" },
				{ "<leader>h", group = "More git" },
				{ "<leader>r", group = "[R]ename" },
				{ "<leader>s", group = "[S]earch" },
				{ "<leader>w", group = "[W]orkspace" },
			}
		},
	},

	-- Fuzzy finder UI
	{
		"nvim-telescope/telescope.nvim",
		branch = "0.1.x",
		dependencies = {
			"nvim-lua/plenary.nvim",
			{
				"nvim-telescope/telescope-fzf-native.nvim",
				build = "make",
				cond = function()
					return vim.fn.executable("make") == 1
				end,
			},
		},
		keys = {
			-- General
			{
				"<C-f>",
				"<cmd>Telescope current_buffer_fuzzy_find theme=dropdown winblend=10 previewer=true<cr>",
				desc = "[/] Fuzzily search in current buffer",
				silent = true,
			},
			{
				"<C-e>",
				"<cmd>Telescope oldfiles only_cwd=true theme=dropdown winblend=10 previewer=true<cr>",
				desc = "Recent files",
				silent = true
			},
			{ "<leader>sf", "<cmd>Telescope find_files<cr>",  desc = "[S]earch [F]iles",        silent = true },
			{ "<leader>sg", "<cmd>Telescope live_grep<cr>",   desc = "[S]earch by [G]rep",      silent = true },
			{ "<leader>sw", "<cmd>Telescope grep_string<cr>", desc = "[S]earch current [W]ord", silent = true },
			{ "<leader>sh", "<cmd>Telescope help_tags<cr>",   desc = "[S]earch [H]elp",         silent = true },
			{ "<leader>sd", "<cmd>Telescope diagnostics<cr>", desc = "[S]earch [D]iagnostics",  silent = true },

			-- Git
			{
				"<leader>gs",
				"<cmd>Telescope git_status theme=dropdown previewer=true<cr>",
				desc = "[G]it [S]tatus",
				silent = true
			},

			-- LSP
			{
				"<leader>sr",
				"<cmd>Telescope lsp_references theme=cursor<cr>",
				desc = "[S]earch [R]eferences",
				silent = true
			},
			{
				"<leader>si",
				"<cmd>Telescope lsp_implementations theme=cursor<cr>",
				desc = "[S]earch [I]implentations",
				silent = true
			},
			{
				"<leader>ss",
				"<cmd>Telescope lsp_workspace_symbols<cr>",
				desc = "[S]earch [S]ymbols",
				silent = true
			},
		},
		opts = function()
			return {
				defaults = {
					mappings = {
						i = {
							["<esc>"] = require("telescope.actions").close,
						},
					},
				},
				extensions = {
					["ui-select"] = {
						require("telescope.themes").get_cursor({}),
					},
				},
			}
		end,
	},

	-- Use Telescope for Code Actions
	"nvim-telescope/telescope-ui-select.nvim",

	-- Diagnostics view
	{
		"folke/trouble.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
	},

	-- Set lualine as statusline
	{
		"nvim-lualine/lualine.nvim",
		event = "VeryLazy",
		opts = {
			options = {
				ignore_focus = { "neo-tree" },
				globalstatus = true,
				icons_enabled = false,
				theme = "onedark",
				component_separators = "|",
				section_separators = "",
			},
			sections = {
				lualine_b = {
					{
						"macro-recording",
						fmt = function()
							local recording_register = vim.fn.reg_recording()
							if recording_register == "" then
								return ""
							else
								return "Recording @" .. recording_register
							end
						end,
					},
				},
			},
		},
	},

	-- Zen mode
	{
		"folke/zen-mode.nvim",
		keys = {
			{
				"<C-z>",
				"<cmd>ZenMode<cr>",
				desc = "Toogle Zen Mode",
				silent = true
			},
		},
		opts = {
			window = {
				width = 130
			},
			plugins = {
				kitty = {
					enabled = true,
					font = "+4"
				}
			}
		}
	}
}
