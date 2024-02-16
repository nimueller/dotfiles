{ pkgs, username, ... }:
let
  libvirt-9_10_0 = pkgs.libvirt.overrideAttrs (oldAttrs: rec {
    version = "9.10.0";
    src = pkgs.fetchurl {
      url = "https://download.libvirt.org/libvirt-${version}.tar.xz";
      sha256 = "06bmvgvly0qa4v2h83vqgbwih6a7dnpwz4fwpiwwb12sx30ayq0h";
    };
  });
in
{
  virtualisation.docker.enable = true;

  boot.kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" "kvm" "kvm_amd" ];
  boot.kernelParams = [ "intel_iommu=on" "iommu=pt" "vfio-pci.ids=1002:6fdf,1002:aaf0" "hugepages=8192" ];
  boot.extraModprobeConfig = "softdep drm pre: vfio-pci";

  virtualisation.libvirtd = {
    enable = true;
    package = libvirt-9_10_0;
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
    quickemu
    virt-manager
    looking-glass-client
  ];
}
