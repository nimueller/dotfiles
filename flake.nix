{
    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
        home-manager = {
            url = "github:nix-community/home-manager";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        hyprland.url = "github:hyprwm/Hyprland";
    };

    outputs = { nixpkgs, home-manager, hyprland, ... }:
    let
        username = "nico";
        system = "x86_64-linux";
        system_x64 = "x86_64-linux";
    in
    {
        nixosConfigurations = {
            desktop = import ./nixos/hosts/desktop { 
                inherit nixpkgs username;
                system = system_x64;
            };
        };

        homeConfigurations = {
            server = home-manager.lib.homeManagerConfiguration {
                pkgs = nixpkgs.legacyPackages.${system};

                extraSpecialArgs = { inherit username; };

                modules = [
                    ./home-manager/default.nix
                    ./home-manager/neovim/default.nix
                ];
            };
            
            desktop = home-manager.lib.homeManagerConfiguration {
                pkgs = nixpkgs.legacyPackages.${system};

                extraSpecialArgs = { inherit username; };

                modules = [
                    hyprland.homeManagerModules.default
                    ./home-manager/default.nix
                    ./home-manager/desktop.nix
                    ./home-manager/neovim/default.nix
                ];
            };
        };
    };
}
