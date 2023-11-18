{
    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
        home-manager = {
            url = "github:nix-community/home-manager";
            inputs.nixpkgs.follows = "nixpkgs";
        };
        hyprland.url = "github:hyprwm/Hyprland";
        spicetify-nix.url = "github:the-argus/spicetify-nix";
        ags.url = "github:Aylur/ags";
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
            server = home-manager.lib.homeManagerConfiguration {
                pkgs = nixpkgs.legacyPackages.${system};

                extraSpecialArgs = { inherit inputs username; };

                modules = [
                    ./home-manager/default.nix
                    ./home-manager/neovim/default.nix
                ];
            };
            
            desktop = home-manager.lib.homeManagerConfiguration {
                pkgs = nixpkgs.legacyPackages.${system};

                extraSpecialArgs = { inherit inputs username; };

                modules = [
                    ./home-manager/desktop.nix
                ];
            };
        };
    };
}
