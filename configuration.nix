{ config, pkgs, lib, ... }:
{
    imports = [
        # Results of hardware scan and home manager installation
        /etc/nixos/hardware-configuration.nix
        <home-manager/nixos>

        # Basic configuration shared among systems
        ./system.nix

        # Services
        ./services.nix

        # System wide packages
        ./packages.nix

        # User specific settings and packages
        ./users.nix
    ];

    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
        "idea-ultimate"
    ];

    system.stateVersion = "23.05";
}
