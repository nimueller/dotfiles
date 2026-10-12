{ pkgs, ... }:
{
  # Python with the iCalendar libraries, for config/quickshell/menus/calendar-dav.py
  quickshell-calendar-python = pkgs.writeShellScriptBin "quickshell-calendar-python" ''
    exec ${
      pkgs.python3.withPackages (ps: [
        ps.icalendar
        ps.recurring-ical-events
      ])
    }/bin/python3 "$@"
  '';

  # Shell scripts: shellcheck runs at build time and the tools they need are
  # on their PATH. TeX Live and Neovim (init-tex, edit-tex) come from the dev
  # module rather than being pulled in here.
  # systemd-inhibit and hyprctl come from the system, like the session they serve
  stay-awake = pkgs.writeShellApplication {
    name = "stay-awake";
    text = builtins.readFile ./scripts/stay-awake.sh;
  };
  init-tex = pkgs.writeShellApplication {
    name = "init-tex";
    text = builtins.readFile ./scripts/init-tex.sh;
  };
  edit-tex = pkgs.writeShellApplication {
    name = "edit-tex";
    runtimeInputs = with pkgs; [ fzf ];
    text = builtins.readFile ./scripts/edit-tex.sh;
  };
}
