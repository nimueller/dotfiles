{ pkgs, lib, ... }:
{
  # Python with the iCalendar libraries, for config/quickshell/menus/calendar-dav.py
  quickshell-calendar-python = pkgs.writeShellScriptBin "quickshell-calendar-python" ''
    exec ${pkgs.python3.withPackages (ps: [ ps.icalendar ps.recurring-ical-events ])}/bin/python3 "$@"
  '';
  recorder = pkgs.writeShellScriptBin "recorder" (builtins.readFile ./scripts/recorder.sh);
  init-tex = pkgs.writeShellScriptBin "init-tex" (builtins.readFile ./scripts/init-tex.sh);
  edit-tex = pkgs.writeShellScriptBin "edit-tex" (builtins.readFile ./scripts/edit-tex.sh);
}
