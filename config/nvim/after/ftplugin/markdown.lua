-- Markdown: read without spelling marks, write with them. Outside insert
-- mode, Vim's spell check and the diagnostics of the spelling servers
-- (codebook, ltex) are hidden; in insert mode they show. Other diagnostics
-- (e.g. marksman's) always show.
local buf = vim.api.nvim_get_current_buf()
local spellers = { codebook = true, ltex = true }

local function spelling(on)
	vim.opt_local.spell = on
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
		if spellers[client.name] then
			for _, pull in ipairs({ false, true }) do
				vim.diagnostic.enable(on, { bufnr = buf, ns_id = vim.lsp.diagnostic.get_namespace(client.id, pull) })
			end
		end
	end
end

local group = vim.api.nvim_create_augroup("markdown_spelling_" .. buf, { clear = true })
vim.api.nvim_create_autocmd("InsertEnter", { group = group, buffer = buf, callback = function() spelling(true) end })
vim.api.nvim_create_autocmd("InsertLeave", { group = group, buffer = buf, callback = function() spelling(false) end })
-- The servers attach after the filetype is set
vim.api.nvim_create_autocmd("LspAttach", {
	group = group,
	buffer = buf,
	callback = function()
		spelling(vim.fn.mode() == "i")
	end,
})

spelling(false)
