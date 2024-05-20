{
  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://hyprland.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
    spicetify-nix.url = "github:the-argus/spicetify-nix";
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
