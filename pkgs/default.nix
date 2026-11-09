{ pkgs, ... }:
let
  # A command from scripts/<name>.py. check.sh lints it (ruff, pyright)
  # instead of the writer's flake8 (doCheck).
  pythonScript =
    name:
    pkgs.writers.writePython3Bin name { doCheck = false; } (builtins.readFile ./scripts/${name}.py);

  # A command from scripts/<name>.sh: shellcheck runs at build time, and the
  # given tools are on its PATH
  shellScript =
    name: runtimeInputs:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = builtins.readFile ./scripts/${name}.sh;
    };
in
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
        emoji=${pkgs.unicode-emoji}/share/unicode/emoji/emoji-test.txt
        python3 ${./emoji.py} "$emoji" "$out" \
          $cldr/annotations/{en,de}.xml \
          $cldr/annotationsDerived/{en,de}.xml
      '';

  # Preloaded into Nautilus: keeps it running, and its start from waiting
  # for the portal (nautilus-preload.c)
  nautilus-preload = pkgs.runCommandCC "nautilus-preload" { } ''
    mkdir -p $out/lib
    $CC -shared -fPIC -O2 -o $out/lib/nautilus-preload.so ${./nautilus-preload.c}
  '';

  # Files' sidebar shows the connected phones' storage in the section of
  # cloud providers, like Nextcloud's: kdeconnect.py in the bar
  # (config/quickshell/menus) provides it, and libcloudproviders finds it
  # through this entry. A package, as it only looks in XDG_DATA_DIRS, which
  # has ~/.nix-profile/share but not ~/.local/share.
  phones-in-files = pkgs.writeTextDir "share/applications/dotfiles-phones.desktop" ''
    [Desktop Entry]
    Type=Application
    Name=Phones in Files
    Exec=true
    NoDisplay=true
    Implements=org.freedesktop.CloudProviders

    [org.freedesktop.CloudProviders]
    BusName=io.github.nimueller.dotfiles.Phones
    ObjectPath=/io/github/nimueller/dotfiles/Phones
  '';

  # Installed software against system/packages/*.txt and the Flatpaks in
  # home-manager/desktop/flatpak.nix
  pkg-sync = pythonScript "pkg-sync";
  # After an update: reboot now, later or not at all (Updates.qml, the
  # `upgrade` alias); pacman comes from the system
  reboot-check = pythonScript "reboot-check";

  # TeX Live and Neovim (init-tex, edit-tex) come from the dev module rather
  # than being pulled in here. systemd-inhibit and hyprctl come from the
  # system, like the session they serve.
  stay-awake = shellScript "stay-awake" [ ];
  # Ends the Sunshine stream from the power menu (config/quickshell/menus/power.qml)
  sunshine-disconnect = shellScript "sunshine-disconnect" (
    with pkgs;
    [
      curl
      libsecret
      libnotify
      coreutils
    ]
  );
  # pgrep comes from the system too
  after-unlock = shellScript "after-unlock" [ ];
  # The lock screen, with the on-screen keyboard in the touch mode and a
  # Caps Lock warning (config/hypr/hyprlock.conf); busctl, pgrep and hyprctl
  # come from the system
  lock-screen = shellScript "lock-screen" [ pkgs.jq ];
  # The media player on the lock screen (config/hypr/hyprlock.conf);
  # playerctl comes from home-manager/desktop
  lock-media = pythonScript "lock-media";
  # The time left after too many wrong passwords at the lock screen
  # (config/hypr/hyprlock.conf, system/pam-hyprlock)
  lock-lockout = pythonScript "lock-lockout";
  # Dims and suspends laptops when idle (config/hypr/hypridle.conf);
  # brightnessctl, busctl and systemctl come from the system
  laptop-idle = shellScript "laptop-idle" [ ];
  # Keeps Discord's logs of calls (timer in home-manager/desktop/default.nix)
  discord-call-logs = pythonScript "discord-call-logs";
  init-tex = shellScript "init-tex" [ ];
  edit-tex = shellScript "edit-tex" [ pkgs.fzf ];
}
