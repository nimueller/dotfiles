-- Enable a language server only when it's installed: the dev module
-- (home-manager/dev) installs them on the desktop, headless machines run
-- Neovim without them.
-- A command given as a function starts the server some other way, which
-- counts as installed
local function isInstalled(name)
    local config = vim.lsp.config[name] or {}
    local command = config.cmd
    if type(command) == "function" then
        return true
    end
    if type(command) == "table" then
        return vim.fn.executable(command[1]) == 1
    end
    return false
end

local function enable(name)
    if isInstalled(name) then
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
