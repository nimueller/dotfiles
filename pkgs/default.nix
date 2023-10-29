{ pkgs, lib, ... }:
{
    hyprshot = pkgs.stdenv.mkDerivation rec {
        name = "hyprshot";
        version = "1.2.3";

        src = builtins.fetchurl {
            url = "https://github.com/Gustash/Hyprshot/archive/refs/tags/${version}.tar.gz";
            sha256 = "03ppmj44vg28vq3m7f0igg3i6x97gmr6mj1nqd05kxwksznlxqq1";
        };

        installPhase = "mkdir -p $out/bin; cp hyprshot $out/bin";
    };

    eww-wayland-tray = (pkgs.eww-wayland.overrideAttrs (drv: rec {
        version = "tray-3";
        src = pkgs.fetchFromGitHub {
            owner = "ralismark";
            repo = "eww";
            rev = "a82ed62c25ba50f28dc8c3d57efe440d51d6136b";
            sha256 = "sha256-vxMGAa/RTsMADPK4dM/28SV2ktCT0DenYvGsHZ4IJ8c=";
        };
        cargoDeps = drv.cargoDeps.overrideAttrs (lib.const {
            inherit src;
            outputHash = "sha256-3B81cTIVt/cne6I/gKBgX4zR5w0UU60ccrFGV1nNCoA=";
        });
        buildInputs = drv.buildInputs ++ (with pkgs; [ glib librsvg libdbusmenu-gtk3 ]);
    }));

    recorder = pkgs.writeShellScriptBin "recorder" (builtins.readFile ./scripts/recorder.sh);
    applauncher = pkgs.writeShellScriptBin "applauncher" (builtins.readFile ./scripts/applauncher.sh);
}
