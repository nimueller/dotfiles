{
    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
        home-manager = {
            url = "github:nix-community/home-manager";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        hyprland.url = "github:hyprwm/Hyprland";
        spicetify-nix.url = "github:the-argus/spicetify-nix";
        neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
    };

    outputs = { nixpkgs, home-manager, ... } @ inputs:
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
            headless = home-manager.lib.homeManagerConfiguration {
                pkgs = nixpkgs.legacyPackages.${system};

                extraSpecialArgs = { inherit inputs username; };

                modules = [
                    ./home-manager/headless
                ];
            };
            
            desktop = home-manager.lib.homeManagerConfiguration {
                pkgs = nixpkgs.legacyPackages.${system};

                extraSpecialArgs = { inherit inputs username; };

                modules = [
                    ./home-manager/desktop
                ];
            };

            runner = home-manager.lib.homeManagerConfiguration {
                pkgs = nixpkgs.legacyPackages.${system};

                extraSpecialArgs = { 
                    inherit inputs;
                    username = "runner";
                };

                modules = [
                    ./home-manager/headless
                ];
            };

        };
    };
}
