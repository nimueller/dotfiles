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

  # The launcher's emoji search: names from Unicode, English and German
  # keywords from CLDR (config/quickshell/menus/Launcher.qml)
  quickshell-emoji =
    pkgs.runCommand "quickshell-emoji.json" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        cldr=${pkgs.cldr-annotations}/share/unicode/cldr/common
        python3 ${./emoji.py} ${pkgs.unicode-emoji}/share/unicode/emoji/emoji-test.txt $out \
          $cldr/annotations/{en,de}.xml $cldr/annotationsDerived/{en,de}.xml
      '';

  # Shell scripts: shellcheck runs at build time and the tools they need are
  # on their PATH. TeX Live and Neovim (init-tex, edit-tex) come from the dev
  # module rather than being pulled in here.
  # systemd-inhibit and hyprctl come from the system, like the session they serve
  stay-awake = pkgs.writeShellApplication {
    name = "stay-awake";
    text = builtins.readFile ./scripts/stay-awake.sh;
  };
  # busctl comes from the system too
  after-unlock = pkgs.writeShellApplication {
    name = "after-unlock";
    text = builtins.readFile ./scripts/after-unlock.sh;
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
