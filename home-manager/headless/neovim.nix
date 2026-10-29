{ pkgs, ... }:
{
  # Neovim and what its plugins need everywhere. Language servers, formatters and
  # toolchains are in ../dev (desktop only); the Neovim config enables only
  # the servers that are installed.
  home.packages = with pkgs; [
    neovim # the editor itself, so headless installs on any distribution have it

    # Neovim plugin package dependencies
    luarocks
    ripgrep
    fd
    tree-sitter
  ];
}
