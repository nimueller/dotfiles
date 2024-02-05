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
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
			"MunifTanjim/nui.nvim",
			-- "3rd/image.nvim", -- Optional image support in preview window: See `# Preview Mode` for more information
		},
		keys = {
			{ "<leader>ft", ":Neotree focus<CR>", desc = "[F]ile [T]ree", silent = true },
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
		opts = {},
	},

	-- Display VIM buffers as tabs to act like a real IDE
	{
		"akinsho/bufferline.nvim",
		version = "*",
		dependencies = "nvim-tree/nvim-web-devicons",
		opts = {
			options = {
				-- style_preset = require('bufferline').style_preset.slant,
				close_command = function(n)
					require("mini.bufremove").delete(n, false)
				end,
				right_mouse_command = function(n)
					require("mini.bufremove").delete(n, false)
				end,
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
					},
				},
			},
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
			{
				"<leader>?",
				"<cmd>Telescope oldfiles<cr>",
				desc = "[?] Find recently opened files",
				silent = true,
			},
			{
				"<leader><space>",
				"<cmd>Telescope buffers<cr>",
				desc = "[ ] Find existing buffers",
				silent = true,
			},
			{
				"<leader>/",
				function()
					require("telescope.builtin").current_buffer_fuzzy_find(require("telescope.themes").get_dropdown({
						winblend = 10,
						previewer = false,
					}))
				end,
				desc = "[/] Fuzzily search in current buffer",
				silent = true,
			},
			{ "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "[F]ind [H]elp", silent = true },
			{ "<leader>gf", "<cmd>Telescope git_files<cr>", desc = "Search [G]it [F]iles", silent = true },
			{ "<leader>sf", "<cmd>Telescope find_files<cr>", desc = "[S]earch [F]iles", silent = true },
			{ "<leader>sh", "<cmd>Telescope help_tags<cr>", desc = "[S]earch [H]elp", silent = true },
			{ "<leader>sw", "<cmd>Telescope grep_string<cr>", desc = "[S]earch current [W]ord", silent = true },
			{ "<leader>sg", "<cmd>Telescope live_grep<cr>", desc = "[S]earch by [G]rep", silent = true },
			{ "<leader>sd", "<cmd>Telescope diagnostics<cr>", desc = "[S]earch [D]iagnostics", silent = true },
			{ "<leader>sr", "<cmd>Telescope resume<cr>", desc = "[S]earch [R]esume", silent = true },
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
}
