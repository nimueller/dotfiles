# Personal dotfiles using Home Manager on Nix

*Still heavily WIP*

To (re-)build NixOS system (NixOS required):
<pre>
sudo nixos-rebuild switch --flake .#nixos --impure
</pre>

To just update home directory with configured user-specific dotfiles and packages (NixOS not required, only a working
Nix package manager installation):
<pre>
home-manager switch --flake .#desktop
</pre>
