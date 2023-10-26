{ nixpkgs, system, username, ... }:
nixpkgs.lib.nixosSystem {
    specialArgs = { 
        inherit username;
        hostname = "Nico-DESKTOP";
    };

    inherit system;

    modules = [
        ./configuration.nix
    ];
}
