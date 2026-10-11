{ pkgs, ... }:
{
  # What Neovim's plugins need everywhere. Language servers, formatters and
  # toolchains are in ../dev (desktop only); the Neovim config enables only
  # the servers that are installed.
  home.packages = with pkgs; [
    # neovim plugin package dependencies
    luarocks
    ripgrep
    fd
    tree-sitter
  ];
}
