{ pkgs, ... }:
let
  nautilusEnvironment = pkgs.buildEnv {
    name = "nautilus-environment";

    paths = with pkgs; [
      gnome.nautilus
      gnome.nautilus-python
      nautilus-open-any-terminal
    ];
  };
in
{
  home = {
    packages = [
      nautilusEnvironment
    ];
    sessionVariables.NAUTILUS_4_EXTENSION_DIR = "${nautilusEnvironment}/lib";
  };

  dconf = {
    enable = true;
    settings."com/github/stunkymonkey/nautilus-open-any-terminal".terminal = "kitty";
  };
}
