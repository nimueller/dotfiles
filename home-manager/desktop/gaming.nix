{ lib, pkgs, ... }:
{
  programs.mangohud = {
    enable = true;
    settings = {
      cpu_temp = 1;
      gpu_temp = 1;
      fsr = 1;
      hdr = 1;
      gamemode = 1;
      gpu_fan = 1;
      arch = 1;
      ram = 1;
      vram = 1;
      swap = 1;
      wine = 1;
      blacklist = "nautilus";
    };
  };

  # Moonlight sends every key to the host, SUPER and ALT + Tab included, also
  # in a window: Hyprland's binds pause while it holds the keyboard
  # (keyboard-shortcuts-inhibit), CTRL + ALT + SHIFT + Z hands it back.
  # Moonlight.conf also holds the paired hosts and their certificates, so
  # only this one setting is written in (2: always, 1: in fullscreen, 0: never):
  # replaced in [General], or added at its end, or with a new [General].
  home.activation.moonlightCapture = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    conf="''${XDG_CONFIG_HOME:-$HOME/.config}/Moonlight Game Streaming Project/Moonlight.conf"
    run mkdir -p "$(dirname "$conf")"
    if [ ! -e "$conf" ]; then
      run touch "$conf"
    fi
    run ${lib.getExe pkgs.gawk} -i inplace -v setting=capturesyskeys=2 '
      /^\[/ {
        if (in_general && !done) {
          print setting
          done = 1
        }
        in_general = ($0 == "[General]")
      }
      in_general && /^capturesyskeys=/ {
        if (!done) {
          print setting
        }
        done = 1
        next
      }
      {
        print
      }
      ENDFILE {
        if (!done) {
          if (!in_general) {
            print "[General]"
          }
          print setting
        }
      }
    ' "$conf"
  '';
}
