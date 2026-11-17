{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/cb26e71f-cd24-4f0a-bc36-938c6063fd12";
    fsType = "btrfs";
    options = [ "subvol=nixos" "compress=zstd:1" "noatime" ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/cb26e71f-cd24-4f0a-bc36-938c6063fd12";
    fsType = "btrfs";
    options = [ "subvol=nix" "compress=zstd:1" "noatime" ];
    neededForBoot = true;
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/cb26e71f-cd24-4f0a-bc36-938c6063fd12";
    fsType = "btrfs";
    options = [ "subvol=home" "compress=zstd:1" "relatime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/49CE-25E6";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
