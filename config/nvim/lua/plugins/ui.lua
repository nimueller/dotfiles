-- A key that runs a Telescope picker, with its options
local function picker(key, command, description)
    return { key, "<cmd>Telescope " .. command .. "<cr>", desc = description, silent = true }
end

local dropdown = "theme=dropdown winblend=10 previewer=true"

return {
    -- Make Vim look nice (entire UI reworked)
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
            close_if_last_window = true,
            sources = { "filesystem", "buffers", "git_status", "document_symbols" },
            open_files_do_not_replace_types = { "terminal", "Trouble", "trouble", "qf", "Outline" },
            filesystem = {
                follow_current_file = true,
                bind_to_cwd = false,
                use_libuv_file_watcher = true,
                window = {
                    mappings = {
                        ["o"] = "system_open",
                        ["<space>"] = {
                            "toggle_preview",
                            config = {
                                use_float = true,
                            },
                        },
                    },
                },
            },
            default_component_configs = {
                indent = {
                    with_expanders = true,
                    expander_collapsed = "",
                    expander_expanded = "",
                    expander_highlight = "NeoTreeExpander",
                },
            },
            commands = {
                -- The file or folder in its default app (xdg-open)
                system_open = function(state)
                    local node = state.tree:get_node()
                    vim.ui.open(node:get_id())
                end,
            },
            event_handlers = {
                {
                    event = "file_open_requested",
                    handler = function()
                        vim.cmd("Neotree close")
                    end,
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
                -- Icons for the mappings only with a Nerd Font
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
            },
        },
    },

    -- Fuzzy finder UI
    {
        "nvim-telescope/telescope.nvim",
        branch = "0.1.x",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-telescope/telescope-ui-select.nvim",
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
            picker("<C-f>", "current_buffer_fuzzy_find " .. dropdown, "[/] Fuzzily search in current buffer"),
            picker("<C-e>", "oldfiles only_cwd=true " .. dropdown, "Recent files"),
            picker("<leader>sf", "find_files", "[S]earch [F]iles"),
            picker("<leader>sg", "live_grep", "[S]earch by [G]rep"),
            picker("<leader>sw", "grep_string", "[S]earch current [W]ord"),
            picker("<leader>sh", "help_tags", "[S]earch [H]elp"),
            picker("<leader>sd", "diagnostics", "[S]earch [D]iagnostics"),

            -- Git
            picker("<leader>gs", "git_status theme=dropdown previewer=true", "[G]it [S]tatus"),

            -- LSP
            picker("<leader>sr", "lsp_references theme=cursor", "[S]earch [R]eferences"),
            picker("<leader>si", "lsp_implementations theme=cursor", "[S]earch [I]mplementations"),
            picker("<leader>ss", "lsp_workspace_symbols", "[S]earch [S]ymbols"),
        },
        config = function(_, opts)
            local telescope = require("telescope")
            telescope.setup(opts)
            telescope.load_extension("ui-select")
        end,
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
                            end
                            return "Recording @" .. recording_register
                        end,
                    },
                },
            },
        },
    },

    {
        "MeanderingProgrammer/render-markdown.nvim",
        dependencies = { "nvim-treesitter/nvim-treesitter", "echasnovski/mini.nvim" },
        ft = { "markdown" },
        opts = {
            completions = { lsp = { enabled = true }, blink = { enabled = true } },
            -- Keep the cursor line rendered too; only the line being edited in
            -- insert mode shows its source
            anti_conceal = { enabled = false },
            win_options = { concealcursor = { rendered = "nc" } },
        },
    },

    -- Zen mode
    {
        "folke/zen-mode.nvim",
        keys = {
            {
                "<C-z>",
                "<cmd>ZenMode<cr>",
                desc = "Toggle Zen mode",
                silent = true,
            },
        },
        opts = {
            window = {
                width = 130,
            },
            plugins = {
                kitty = {
                    enabled = true,
                    font = "+4",
                },
            },
            on_open = function()
                vim.cmd("RenderMarkdown buf_disable")
            end,
            on_close = function()
                vim.cmd("RenderMarkdown buf_enable")
            end,
        },
    },
}
