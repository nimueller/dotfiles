{ config, pkgs, lib, ... }:
{
    imports = [
        # Results of hardware scan and home manager installation
        /etc/nixos/hardware-configuration.nix

        # Basic configuration shared among systems
        ./system.nix

        # Services
        ./services.nix

        # System wide packages
        ./packages.nix

        # User specific settings and packages
        ./users.nix
    ];

    nix.settings.experimental-features = [
        "nix-command"
        "flakes"
    ];
    system.stateVersion = "23.05";
}
