{ config, lib, pkgs, modulesPath, hostSpec, ... }:

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
  boot.kernelModules =
    lib.optional (hostSpec.cpu == "intel") "kvm-intel"
    ++ lib.optional (hostSpec.cpu == "amd") "kvm-amd";
  boot.extraModulePackages = [ ];

  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/${hostSpec.rootLabel}";
    fsType = "btrfs";
    options = [ "subvol=nixos" "compress=zstd:1" "noatime" ];
  };

  fileSystems."/nix" = lib.mkDefault {
    device = "/dev/disk/by-label/${hostSpec.rootLabel}";
    fsType = "btrfs";
    options = [ "subvol=nix" "compress=zstd:1" "noatime" ];
    neededForBoot = true;
  };

  fileSystems."/home" = lib.mkDefault {
    device = "/dev/disk/by-label/${hostSpec.rootLabel}";
    fsType = "btrfs";
    options = [ "subvol=home" "compress=zstd:1" "relatime" ];
  };

  fileSystems."/boot" = lib.mkDefault {
    device = "/dev/disk/by-label/${hostSpec.bootLabel}";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault hostSpec.system;
  hardware.cpu.intel.updateMicrocode = lib.mkIf (hostSpec.cpu == "intel") (lib.mkDefault config.hardware.enableRedistributableFirmware);
  hardware.cpu.amd.updateMicrocode = lib.mkIf (hostSpec.cpu == "amd") (lib.mkDefault config.hardware.enableRedistributableFirmware);

  hardware.graphics = {
    enable = true;
    extraPackages = lib.optionals (hostSpec.gpu == "intel") (with pkgs; [
      intel-media-driver
      vpl-gpu-rt
    ]);
  };
}
