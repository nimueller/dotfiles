{ pkgs, wrapQtAppsHook, ... }:
with pkgs;
stdenv.mkDerivation {
    name = "xwaylandvideobridge2";
    src = fetchFromGitLab {
        domain = "invent.kde.org";
        owner = "system";
        repo = "xwaylandvideobridge";
        rev = "b327a9b1759ff75beaf133dbb91d867e0dc37305";
        hash = "sha256-lEPtq6gEgfMpN5tsk7OEug8kMz5dXou/bsd+n1+J0TI=";
    };

    nativeBuildInputs = [
        wrapQtAppsHook
        cmake
        extra-cmake-modules
        pkg-config
    ];

    buildInputs = [
        qt5.qtbase
        qt5.qtquickcontrols2
        qt5.qtx11extras
        libsForQt5.kdelibs4support
        (libsForQt5.kpipewire.overrideAttrs (oldAttrs: {
            version = "unstable-2023-03-28";

            src = fetchFromGitLab {
                domain = "invent.kde.org";
                owner = "plasma";
                repo = "kpipewire";
                rev = "ed99b94be40bd8c5b7b2a2f17d0622f11b2ab7fb";
                hash = "sha256-KhmhlH7gaFGrvPaB3voQ57CKutnw5DlLOz7gy/3Mzms=";
            };
        }))
    ];

    patches = [ ./xwaylandvideobridge_on_hyprland.patch ];
}
