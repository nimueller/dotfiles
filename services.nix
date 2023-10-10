{ pkgs, ... }:
{
    # GNOME Desktop Environment
    programs.hyprland.enable = true;
    environment.sessionVariables.NIXOS_OZONE_WL = "1";

    services.greetd = {
      enable = true;
      settings = rec {
        initial_session = {
          command = "Hyprland";
	  user = "nico";
	};
	default_session = initial_session;
      };
    };

    # services.xserver.enable = true;
    # services.xserver.displayManager.gdm.enable = true;
    # services.xserver.displayManager.gdm.wayland = true;
    # services.xserver.displayManager.autoLogin.enable = true;
    # services.xserver.displayManager.autoLogin.user = "nico";
    # services.xserver.desktopManager.gnome.enable = true;
    # systemd.services."getty@tty1".enable = false;
    # systemd.services."autovt@tty1".enable = false;

    # Configure keymap in X11
    # services.xserver = {
    #     layout = "us";
    #     xkbVariant = "";
    # };

    # Enable CUPS to print documents.
    services.printing.enable = true;

    # Enable sound with pipewire.
    sound.enable = true;
    hardware.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
        # If you want to use JACK applications, uncomment this
        #jack.enable = true;

        # use the example session manager (no others are packaged yet so this is enabled by default,
        # no need to redefine it in your config for now)
        #media-session.enable = true;
    };

    # Enable the OpenSSH daemon.
    services.openssh.enable = true;

    # Flatpak
    services.flatpak.enable = true;

    xdg.portal = {
	enable = true;
	wlr.enable = true;
	extraPortals = with pkgs; [ xdg-desktop-portal-gtk ];
    };


    # Fixes error https://github.com/NixOS/nixpkgs/issues/189851 
    systemd.user.extraConfig = ''
    	DefaultEnvironment="PATH=/run/current-system/sw/bin"
    '';
}
