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
    # Declared Flatpaks (home-manager/desktop/flatpak.nix)
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      nix-flatpak,
      ...
    }:
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
      desktopModules = [
        ./home-manager/headless
        ./home-manager/desktop
        nix-flatpak.homeManagerModules.nix-flatpak
      ];
    in
    {
      # `nix fmt`: nixfmt over every .nix file
      formatter = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
        system: nixpkgs.legacyPackages.${system}.nixfmt-tree
      );

      # The tools of check.sh (`nix develop` for a shell with them): linters
      # for Nix, shell, Python and QML, and a Python with the libraries the
      # helpers import, so pyright knows their types
      devShells = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              nixfmt
              statix
              deadnix
              shellcheck
              ruff
              pyright
              quickshell
              qt6.qtdeclarative
              (python3.withPackages (ps: [
                ps.pygobject3
                ps.pygobject-stubs
                ps.icalendar
                ps.recurring-ical-events
              ]))
            ];
          };
        }
      );

      homeConfigurations = {
        headless = mkHome { modules = [ ./home-manager/headless ]; };

        headless_aarch64 = mkHome {
          system = "aarch64-linux";
          modules = [ ./home-manager/headless ];
        };

        desktop = mkHome { modules = desktopModules; };

        # ARM laptops; what has no aarch64 build is left out
        # in the modules themselves (stdenv.hostPlatform.isx86_64). Without
        # the dev tools: TeX Live and the toolchains are most of 16 GB.
        desktop_aarch64 = mkHome {
          system = "aarch64-linux";
          modules = desktopModules ++ [ { devTools = false; } ];
        };

        # GitHub Actions runner (CI)
        runner = mkHome {
          username = "runner";
          modules = [ ./home-manager/headless ];
        };
      };
    };
}
