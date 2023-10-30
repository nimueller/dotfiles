# Personal dotfiles
*Still heavily WIP*
## Home-Manager configuration (any OS)
### Installing Nix package manager (skip if Nix is already installed)
<pre>
  curl -L https://nixos.org/nix/install | sh
  mkdir -p $HOME/.config/nix/
  echo "experimental-features = nix-command flakes" >> $HOME/.config/nix/nix.conf
  source $HOME/.nix-profile/etc/profile.d/nix.sh
</pre>

### Installing Home-Manager (skip if Home-Manager is already installed)
<pre>
  nix run home-manager/master -- init --switch
</pre>

### Updating dotfiles
<pre>
  home-manager switch --flake github:LegendSalocin/dotfiles#server
</pre>

## NixOS configuration (NixOS required)
To (re-)build entire NixOS system:
<pre>
sudo nixos-rebuild switch --flake .#desktop
</pre>
