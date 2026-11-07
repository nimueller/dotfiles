-- Markdown: read without spelling marks, write with them. Outside insert
-- mode, Vim's spell check and the diagnostics of the spelling servers
-- (codebook, ltex) are hidden; in insert mode they show. Other diagnostics
-- (e.g. marksman's) always show.
local buf = vim.api.nvim_get_current_buf()
local spellers = { codebook = true, ltex = true }

-- A server's diagnostics come in two namespaces: pushed and pulled ones
local function showDiagnostics(client, on)
    for _, isPull in ipairs({ false, true }) do
        local namespace = vim.lsp.diagnostic.get_namespace(client.id, isPull)
        vim.diagnostic.enable(on, { bufnr = buf, ns_id = namespace })
    end
end

local function spelling(on)
    vim.opt_local.spell = on
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
        if spellers[client.name] then
            showDiagnostics(client, on)
        end
    end
end

local group = vim.api.nvim_create_augroup("markdown_spelling_" .. buf, { clear = true })
vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    buffer = buf,
    callback = function()
        spelling(true)
    end,
})
vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    buffer = buf,
    callback = function()
        spelling(false)
    end,
})
-- The servers attach after the filetype is set
vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    buffer = buf,
    callback = function()
        spelling(vim.fn.mode() == "i")
    end,
})

spelling(false)
