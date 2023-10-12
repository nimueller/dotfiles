{
    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
        home-manager = {
            url = "github:nix-community/home-manager";
            inputs.nixpkgs.follows = "nixpkgs";
        };
    };

    outputs = { nixpkgs, home-manager,  ... }:
    let
        system = "x86_64-linux";
        modules = [
            ./nixos/configuration.nix
        ];
    in
    {
        nixosConfigurations = {
            nixos = nixpkgs.lib.nixosSystem {
                inherit modules system;
            };
        };

        homeConfigurations = {
            nico = home-manager.lib.homeManagerConfiguration {
                pkgs = nixpkgs.legacyPackages.${system};
                modules = [
                    ./home-manager/home.nix
                ];
            };
        };
    };
}
