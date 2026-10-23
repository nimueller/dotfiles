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
  # only this one setting is written in (2: always, 1: in fullscreen, 0: never)
  home.activation.moonlightCapture = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    conf="''${XDG_CONFIG_HOME:-$HOME/.config}/Moonlight Game Streaming Project/Moonlight.conf"
    run mkdir -p "$(dirname "$conf")"
    [ -e "$conf" ] || run touch "$conf"
    run ${lib.getExe pkgs.gawk} -i inplace '
      /^\[/ { if (general && !done) { print "capturesyskeys=2"; done = 1 } general = ($0 == "[General]") }
      general && /^capturesyskeys=/ { if (!done) print "capturesyskeys=2"; done = 1; next }
      { print }
      ENDFILE { if (!done) { if (!general) print "[General]"; print "capturesyskeys=2" } }
    ' "$conf"
  '';
}
