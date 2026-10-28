# GUI apps from Flathub, installed and removed by home-manager switch
# (nix-flatpak), in the user installation. Preferred over the AUR: sandboxed,
# reviewed builds, and Flatpak brings the GPU driver matching the host's
# (also NVIDIA's), which Nix apps on Arch don't get. `pkg-sync` reports what
# differs from this list.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # The sandboxes can't see the Nix store, so they get read access to these
  # files in the dotfiles themselves, linked directly (activation below)
  dotfiles = "~/${lib.removePrefix "${config.home.homeDirectory}/" config.dotfiles}";
  proxy = "${config.dotfiles}/config/keepassxc/keepassxc-proxy.py";
  keepassxcSocket = "xdg-run/app/org.keepassxc.KeePassXC";

  # KeePassXC-Browser: the browsers start the proxy from the dotfiles, which
  # talks to KeePassXC's socket (config/keepassxc/keepassxc-proxy.py)
  braveHost = pkgs.writeText "org.keepassxc.keepassxc_browser.json" (
    builtins.toJSON {
      name = "org.keepassxc.keepassxc_browser";
      description = "KeePassXC integration with native messaging support";
      path = proxy;
      type = "stdio";
      allowed_origins = [
        "chrome-extension://pdffhmdngciaglkoonimfcmckehcpafo/"
        "chrome-extension://oboonakemofpalcgghocfoadofidjkkk/"
      ];
    }
  );
  zenHost = pkgs.writeText "org.keepassxc.keepassxc_browser.json" (
    builtins.toJSON {
      name = "org.keepassxc.keepassxc_browser";
      description = "KeePassXC integration with native messaging support";
      path = proxy;
      type = "stdio";
      allowed_extensions = [ "keepassxc-browser@keepassxc.org" ];
    }
  );
in
{
  services.flatpak = {
    enable = true;
    packages = [
      "app.zen_browser.zen" # Zen browser
      "com.brave.Browser"
      "de.bund.ausweisapp.ausweisapp2" # AusweisApp (eID)
      "org.libreoffice.LibreOffice"
    ]
    # No aarch64 build on Flathub (Yubico), or no use without Steam,
    # which is x86 only (ProtonPlus)
    ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
      "com.vysp3r.ProtonPlus" # Proton versions for Steam and Lutris
      "com.yubico.yubioath" # Yubico Authenticator
    ];
    overrides = {
      # Its flags (config/brave-flags.conf: Wayland) and KeePassXC
      "com.brave.Browser".Context.filesystems = [
        keepassxcSocket
        "${dotfiles}/config/brave-flags.conf:ro"
        "${dotfiles}/config/keepassxc:ro"
      ];
      # KeePassXC; ~/.mozilla for the proxy's entry, as on the host
      "app.zen_browser.zen".Context = {
        filesystems = [
          keepassxcSocket
          "${dotfiles}/config/keepassxc:ro"
        ];
        persistent = [ ".mozilla" ];
      };
    };
    # Undeclared apps in the user installation go; the system installation
    # isn't touched
    uninstallUnmanaged = true;
    # pacman -Syu doesn't update Flatpaks: a daily timer does (browsers
    # need their security updates), switching doesn't wait for downloads
    update = {
      onActivation = false;
      auto = {
        enable = true;
        onCalendar = "daily";
      };
    };
  };

  # A sandbox gets KeePassXC's socket folder only if it exists when the
  # browser starts, which is usually before KeePassXC: created at login.
  # KeePassXC uses it as it is and never removes it
  systemd.user.tmpfiles.rules = [ "d %t/app/org.keepassxc.KeePassXC 0700 - - -" ];

  # Brave's flags file and the browsers' KeePassXC entries, inside their
  # sandboxes: a direct link to the dotfiles (the sandbox can't follow one
  # through the Nix store), and copies of the entries
  home.activation.flatpakBrowsers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    brave=$HOME/.var/app/com.brave.Browser/config
    zen=$HOME/.var/app/app.zen_browser.zen/.mozilla
    run mkdir -p "$brave/BraveSoftware/Brave-Browser/NativeMessagingHosts" "$zen/native-messaging-hosts"
    run ln -sfn ${config.dotfiles}/config/brave-flags.conf "$brave/brave-flags.conf"
    run install -m 644 ${braveHost} "$brave/BraveSoftware/Brave-Browser/NativeMessagingHosts/org.keepassxc.keepassxc_browser.json"
    run install -m 644 ${zenHost} "$zen/native-messaging-hosts/org.keepassxc.keepassxc_browser.json"
  '';

  # For pkg-sync
  xdg.configFile."pkg-sync/flatpaks".text = lib.concatMapStrings (
    p: "${if builtins.isString p then p else p.appId}\n"
  ) config.services.flatpak.packages;
}
