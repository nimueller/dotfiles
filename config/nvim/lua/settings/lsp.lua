-- General
vim.lsp.enable("codebook")

-- LaTeX and Markdown
vim.lsp.enable("ltex")
vim.lsp.enable("marksman")

-- Lua
vim.lsp.enable("lua_ls")

-- Nix
vim.lsp.enable("nil_ls")
vim.lsp.config("nil_ls", {
	settings = {
		nix = {
			formatting = {
				command = "nixpkgs-fmt",
			},
			maxMemoryMB = 4096,
			flake = {
				autoArchive = true,
				autoEvalInputs = true,
				nixpkgsInputName = "nixpkgs",
			},
		},
	},
})
vim.lsp.enable("statix")

-- Hyprland
vim.lsp.enable("hyprls")

-- C++
vim.lsp.enable("clangd")

-- Python
vim.lsp.enable("pyright")
vim.lsp.enable("pylyzer")

-- Enable diagnostic virtual_text
vim.diagnostic.config({ virtual_text = true })
