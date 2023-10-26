{ pkgs, username, ... }:
{
    imports = [ 
        # Results of hardware scan
        ./hardware-configuration.nix

        # Common configuration shared by all hosts
        ../../common-configuration.nix

        # Extra virtualization settings
        ./virtualization.nix
    ];

    # Hyprland Desktop Environment
    programs.hyprland.enable = true;
    environment.sessionVariables.NIXOS_OZONE_WL = "1";

    # Greetd as Display Manager
    services.greetd = {
        enable = true;
        settings = rec {
            initial_session = {
                command = "Hyprland";
                user = username;
            };
            default_session = initial_session;
        };
    };

    # Flatpak
    services.flatpak.enable = true;

    # XDG Desktop Portal
    xdg.portal = {
        enable = true;
        wlr.enable = true;
        extraPortals = with pkgs; [ xdg-desktop-portal-gtk ];
    };

    programs.gnome-disks.enable = true;

    # Fixes error https://github.com/NixOS/nixpkgs/issues/189851 
    systemd.user.extraConfig = ''
    	DefaultEnvironment="PATH=/run/current-system/sw/bin"
    '';
}
