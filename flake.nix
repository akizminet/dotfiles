{
  description = "Portable NixOS configuration and user packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    celluloid-src = {
      url = "git+ssh://git@github.com/akizminet/akcelluloid.git";
      flake = false;
    };
    akquick.url = "github:akizminet/akquick";
    akquick.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, celluloid-src, akquick }:
    let
      mkHost =
        { hostName
        , system ? "x86_64-linux"
        , username ? "phamnv"
        , userDescription ? "Nguyen Van Pham"
        , dotfilesDir ? "/home/${username}/dev/dotfiles"
        , cpu ? "intel"
        , gpu ? "intel"
        , bootLabel ? "EFI"
        , rootLabel ? "NIXOS"
        , machineId ? null
        , hashedPasswordFile ? null
        , hardwareClockInLocalTime ? false
        , extraModules ? [ ]
        }:
        let
          hostSpec = {
            inherit
              hostName
              system
              username
              userDescription
              dotfilesDir
              cpu
              gpu
              bootLabel
              rootLabel
              machineId
              hashedPasswordFile
              hardwareClockInLocalTime
              ;
          };
        in
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit self celluloid-src akquick hostSpec;
          };
          modules = [
            { nixpkgs.overlays = [ (final: prev: { pcre = prev.pcre2; }) ]; }
            ./nixos/modules/hardware-generic.nix
            ./nixos/modules/base.nix
            ./nixos/modules/user-packages.nix
          ] ++ extraModules;
        };
    in
    {
      nixosConfigurations = {
        homepc = mkHost {
          hostName = "homepc";
          cpu = "intel";
          gpu = "intel";
          machineId = "e766ad57c4654c84869e2929fd73e0a0";
          hashedPasswordFile = "/var/lib/nixos/phamnv-password-hash";
          hardwareClockInLocalTime = true;
          extraModules = [ ./nixos/hosts/homepc ];
        };
        workstation = self.nixosConfigurations.homepc;
        generic = mkHost { hostName = "workstation"; };
      };
    };
}
