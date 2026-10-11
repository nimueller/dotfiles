-- Enable a language server only when it's installed: the dev module
-- (home-manager/dev) installs them on the desktop, headless machines run
-- Neovim without them.
local function enable(name)
	local cmd = (vim.lsp.config[name] or {}).cmd
	if type(cmd) == "function" or (type(cmd) == "table" and vim.fn.executable(cmd[1]) == 1) then
		vim.lsp.enable(name)
	end
end

-- General
enable("codebook")

-- LaTeX and Markdown
enable("ltex")
enable("marksman")

-- Lua
enable("lua_ls")

-- Nix
enable("nil_ls")
vim.lsp.config("nil_ls", {
	settings = {
		nix = {
			formatting = {
				command = { "nixfmt" },
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
enable("statix")

-- Hyprland
enable("hyprls")

-- C++
enable("clangd")

-- Python
enable("pyright")

-- Go
enable("gopls")

-- Enable diagnostic virtual_text
vim.diagnostic.config({ virtual_text = true })
