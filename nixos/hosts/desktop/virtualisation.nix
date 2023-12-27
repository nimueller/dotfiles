{ pkgs, username, ... }:
{
    virtualisation.docker.enable = true;

    # boot.kernelParams = [ "intel_iommu=on" "iommu=pt" "vfio-pci.ids=10de:2704,10de:22bb" "hugepages=8192" ];
    boot.kernelParams = [ "intel_iommu=on" "iommu=pt" ];
    boot.extraModprobeConfig = "softdep drm pre: vfio-pci";

    virtualisation.libvirtd = {
        enable = true;
        onBoot = "ignore";
        onShutdown = "shutdown";
        qemu.ovmf.enable = true;
        hooks.qemu = {
            events = ./virtualisation_events.sh;
        };
    };

    systemd.tmpfiles.rules = [
        "f /dev/shm/looking-glass 0660 ${username} kvm -"
    ];

    users.users.${username} = {
        extraGroups = [ "docker" "libvirtd" ];
    };

    environment.systemPackages = with pkgs; [
        (writeScriptBin "iommu-groups" ''
#!/usr/bin/env bash
shopt -s nullglob
for g in $(find /sys/kernel/iommu_groups/* -maxdepth 0 -type d | sort -V); do
    echo "IOMMU Group ''${g##*/}:"
    for d in $g/devices/*; do
        echo -e "\t$(lspci -nns ''${d##*/})"
    done;
done;
        '')
        virt-manager
        looking-glass-client
    ];
}
