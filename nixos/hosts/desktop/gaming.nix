{ pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    glfw-wayland
    gamemode
    mangohud
    wineWowPackages.waylandFull
    winetricks
    steam
    lutris
  ];
}
