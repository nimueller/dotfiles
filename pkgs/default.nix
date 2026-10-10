{ pkgs, lib, ... }:
{
  hyprshot = pkgs.stdenv.mkDerivation rec {
    name = "hyprshot";
    version = "1.2.3";

    src = builtins.fetchurl {
      url = "https://github.com/Gustash/Hyprshot/archive/refs/tags/${version}.tar.gz";
      sha256 = "03ppmj44vg28vq3m7f0igg3i6x97gmr6mj1nqd05kxwksznlxqq1";
    };

    installPhase = "mkdir -p $out/bin; cp hyprshot $out/bin";
  };

  # Python with the iCalendar libraries, for config/quickshell/menus/calendar-dav.py
  quickshell-calendar-python = pkgs.writeShellScriptBin "quickshell-calendar-python" ''
    exec ${pkgs.python3.withPackages (ps: [ ps.icalendar ps.recurring-ical-events ])}/bin/python3 "$@"
  '';
  recorder = pkgs.writeShellScriptBin "recorder" (builtins.readFile ./scripts/recorder.sh);
  init-tex = pkgs.writeShellScriptBin "init-tex" (builtins.readFile ./scripts/init-tex.sh);
  edit-tex = pkgs.writeShellScriptBin "edit-tex" (builtins.readFile ./scripts/edit-tex.sh);
}
