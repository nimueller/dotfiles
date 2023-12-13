{ pkgs, lib, ... }:
{
    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
        "nvidia-x11"
        "nvidia-settings"
    ];

    hardware.opengl = {
        enable = true;
        driSupport = true;
        driSupport32Bit = true;
        extraPackages = with pkgs; [
            vaapiVdpau
            libvdpau-va-gl
        ];
    };

    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {
        modesetting.enable = true;
        powerManagement.enable = false;
        powerManagement.finegrained = false;
        open = false;
        nvidiaSettings = true;
    };

}

