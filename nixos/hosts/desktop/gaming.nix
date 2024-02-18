{ pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    glfw-wayland
    gamemode
    mangohud
    wine
    wine64
    steam
    lutris
  ];
}
