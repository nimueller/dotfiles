{ pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    gamemode
    mangohud
    wine
    steam
    lutris
  ];
}
