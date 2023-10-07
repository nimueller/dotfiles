{ pkgs, ... }:
{
    users.users.nico = {
        isNormalUser = true;
        description = "nico";
        extraGroups = [ "networkmanager" "wheel" ];
    };

    home-manager.users.nico = { lib, pkgs, ... }: {
        nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
                     "idea-ultimate"
                   ];

        home = {
            packages = with pkgs; [
                firefox
                jetbrains.idea-ultimate
            ];
            stateVersion = "23.05";
        };

        programs.zsh.enable = true;
    };
}