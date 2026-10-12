return {
	{
		"tpope/vim-sleuth",
		event = { "BufReadPost", "BufNewFile" },
	},

	{
		-- Highlight, edit, and navigate code. The main branch: the old master
		-- branch is frozen and breaks on Neovim 0.12. Parsers are compiled with
		-- the tree-sitter CLI (home-manager/headless/neovim.nix).
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false, -- the main branch doesn't support lazy loading
		build = ":TSUpdate",
		config = function()
			local ts = require("nvim-treesitter")
			ts.install({
				"c", "cpp", "go", "lua", "python", "rust", "tsx", "javascript", "typescript",
				"vimdoc", "vim", "bash", "xml", "html", "markdown", "markdown_inline", "hyprlang",
			})

			-- Highlighting and indentation for every filetype with a parser;
			-- missing parsers are installed the first time they're needed
			local function start(buf, lang)
				if vim.api.nvim_buf_is_valid(buf) and pcall(vim.treesitter.start, buf, lang) then
					vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
				end
			end
			vim.api.nvim_create_autocmd("FileType", {
				callback = function(args)
					local lang = vim.treesitter.language.get_lang(args.match)
					if not lang then
						return
					end
					if vim.list_contains(ts.get_installed(), lang) then
						start(args.buf, lang)
					elseif vim.list_contains(ts.get_available(), lang) then
						ts.install(lang):await(function()
							vim.schedule(function()
								start(args.buf, lang)
							end)
						end)
					end
				end,
			})

			-- Incremental selection on Neovim's own an/in (visual mode)
			vim.keymap.set("n", "<C-space>", "van", { remap = true, desc = "Select the node under the cursor" })
			vim.keymap.set("x", "<C-space>", "an", { remap = true, desc = "Grow the selection to the parent node" })
			vim.keymap.set("x", "<M-space>", "in", { remap = true, desc = "Shrink the selection to a child node" })
		end,
	},

	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		branch = "main",
		event = { "BufReadPost", "BufNewFile" },
		config = function()
			require("nvim-treesitter-textobjects").setup({
				select = { lookahead = true }, -- jump forward to the next object, like targets.vim
				move = { set_jumps = true },
			})

			local select = require("nvim-treesitter-textobjects.select")
			for keys, object in pairs({
				aa = "@parameter.outer",
				ia = "@parameter.inner",
				af = "@function.outer",
				["if"] = "@function.inner",
				ac = "@class.outer",
				ic = "@class.inner",
			}) do
				vim.keymap.set({ "x", "o" }, keys, function()
					select.select_textobject(object, "textobjects")
				end, { desc = "Select " .. object })
			end

			local move = require("nvim-treesitter-textobjects.move")
			for keys, target in pairs({
				["]m"] = { "goto_next_start", "@function.outer" },
				["]]"] = { "goto_next_start", "@class.outer" },
				["]M"] = { "goto_next_end", "@function.outer" },
				["]["] = { "goto_next_end", "@class.outer" },
				["[m"] = { "goto_previous_start", "@function.outer" },
				["[["] = { "goto_previous_start", "@class.outer" },
				["[M"] = { "goto_previous_end", "@function.outer" },
				["[]"] = { "goto_previous_end", "@class.outer" },
			}) do
				vim.keymap.set({ "n", "x", "o" }, keys, function()
					move[target[1]](target[2], "textobjects")
				end, { desc = "Move to " .. target[2] })
			end

			local swap = require("nvim-treesitter-textobjects.swap")
			vim.keymap.set("n", "<leader>sa", function()
				swap.swap_next("@parameter.inner")
			end, { desc = "Swap with the next parameter" })
			vim.keymap.set("n", "<leader>sA", function()
				swap.swap_previous("@parameter.inner")
			end, { desc = "Swap with the previous parameter" })
		end,
	},

	{
		-- Close and rename HTML/JSX tags in pairs
		"windwp/nvim-ts-autotag",
		event = { "BufReadPost", "BufNewFile" },
		opts = {
			opts = {
				enable_close = true,
				enable_rename = true,
				enable_close_on_slash = true,
			},
		},
	},

	-- Easily surround text
	{
		"kylechui/nvim-surround",
		version = "*", -- Use for stability; omit to use `main` branch for the latest features
		event = { "BufReadPost", "BufNewFile" },
		config = function()
			require("nvim-surround").setup({
				-- Configuration here, or leave empty to use defaults
			})
		end,
	},

	-- Add indentation guides even on blank lines
	{
		"lukas-reineke/indent-blankline.nvim",
		event = { "BufReadPost", "BufNewFile" },
		main = "ibl",
		opts = {},
	},

	-- "gc" to comment visual regions/lines
	{
		"numToStr/Comment.nvim",
		event = { "BufReadPost", "BufNewFile" },
		opts = {},
	},

	-- Vim Sneak
	{
		"justinmk/vim-sneak",
		event = { "BufReadPost", "BufNewFile" },
	}
}
