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
  # home-manager/desktop/flatpak.nix. Python scripts: check.sh lints them
  # (ruff, pyright) instead of the writer's flake8 (doCheck)
  pkg-sync = pkgs.writers.writePython3Bin "pkg-sync" { doCheck = false; } (
    builtins.readFile ./scripts/pkg-sync.py
  );

  # Shell scripts: shellcheck runs at build time and the tools they need are
  # on their PATH. TeX Live and Neovim (init-tex, edit-tex) come from the dev
  # module rather than being pulled in here.
  # systemd-inhibit and hyprctl come from the system, like the session they serve
  stay-awake = pkgs.writeShellApplication {
    name = "stay-awake";
    text = builtins.readFile ./scripts/stay-awake.sh;
  };
  # Ends the Sunshine stream from the power menu (config/quickshell/menus/power.qml)
  sunshine-disconnect = pkgs.writeShellApplication {
    name = "sunshine-disconnect";
    runtimeInputs = with pkgs; [
      curl
      libsecret
      libnotify
      coreutils
    ];
    text = builtins.readFile ./scripts/sunshine-disconnect.sh;
  };
  # pgrep comes from the system too
  after-unlock = pkgs.writeShellApplication {
    name = "after-unlock";
    text = builtins.readFile ./scripts/after-unlock.sh;
  };
  # The lock screen, with the on-screen keyboard in the touch mode and a
  # Caps Lock warning (config/hypr/hyprlock.conf); busctl, pgrep and hyprctl
  # come from the system
  lock-screen = pkgs.writeShellApplication {
    name = "lock-screen";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ./scripts/lock-screen.sh;
  };
  # The media player on the lock screen (config/hypr/hyprlock.conf);
  # playerctl comes from home-manager/desktop
  lock-media = pkgs.writers.writePython3Bin "lock-media" { doCheck = false; } (
    builtins.readFile ./scripts/lock-media.py
  );
  # The time left after too many wrong passwords at the lock screen
  # (config/hypr/hyprlock.conf, system/pam-hyprlock)
  lock-lockout = pkgs.writers.writePython3Bin "lock-lockout" { doCheck = false; } (
    builtins.readFile ./scripts/lock-lockout.py
  );
  # Dims and suspends laptops when idle (config/hypr/hypridle.conf);
  # brightnessctl, busctl and systemctl come from the system
  laptop-idle = pkgs.writeShellApplication {
    name = "laptop-idle";
    text = builtins.readFile ./scripts/laptop-idle.sh;
  };
  # Turns the built-in screen with the device in the touch mode
  # (config/hypr/modes.lua); monitor-sensor (iio-sensor-proxy) and hyprctl
  # come from the system
  auto-rotate = pkgs.writers.writePython3Bin "auto-rotate" { doCheck = false; } (
    builtins.readFile ./scripts/auto-rotate.py
  );
  # Keeps Discord's logs of calls (timer in home-manager/desktop/default.nix)
  discord-call-logs = pkgs.writers.writePython3Bin "discord-call-logs" { doCheck = false; } (
    builtins.readFile ./scripts/discord-call-logs.py
  );
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
