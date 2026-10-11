{
  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, home-manager, ... }:
    let
      # Unfree packages (Steam, Discord, ...) are allowed everywhere; setting
      # it here instead of in a module spares home-manager a second nixpkgs
      # import
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

      mkHome =
        {
          system ? "x86_64-linux",
          username ? "nico",
          modules,
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor system;
          extraSpecialArgs = { inherit username; };
          modules = [ ./options ] ++ modules;
        };
    in
    {
      homeConfigurations = {
        headless = mkHome { modules = [ ./home-manager/headless ]; };

        headless_aarch64 = mkHome {
          system = "aarch64-linux";
          modules = [ ./home-manager/headless ];
        };

        desktop = mkHome {
          modules = [
            ./home-manager/headless
            ./home-manager/desktop
          ];
        };

        # GitHub Actions runner (CI)
        runner = mkHome {
          username = "runner";
          modules = [ ./home-manager/headless ];
        };
      };
    };
}
