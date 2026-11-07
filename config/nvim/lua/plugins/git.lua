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
                virt_text_pos = "eol",
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

                -- ]c and [c jump between hunks, except in diff mode, where
                -- the built-in and fugitive's keymaps keep them
                local gs = package.loaded.gitsigns
                local function hunkJump(key, jump, description)
                    vim.keymap.set({ "n", "v" }, key, function()
                        if vim.wo.diff then
                            return key
                        end
                        vim.schedule(jump)
                        return "<Ignore>"
                    end, { expr = true, buffer = bufnr, desc = description })
                end
                hunkJump("]c", gs.next_hunk, "Jump to next hunk")
                hunkJump("[c", gs.prev_hunk, "Jump to previous hunk")
            end,
        },
    },
}
