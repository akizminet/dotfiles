{
  description = "NixOS configuration for homepc";

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
      system = "x86_64-linux";
    in
    {
      nixosConfigurations = {
        homepc = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit self celluloid-src akquick; };
          modules = [
            { nixpkgs.overlays = [ (final: prev: { pcre = prev.pcre2; }) ]; }
            ./nixos/configuration.nix
          ];
        };
        workstation = self.nixosConfigurations.homepc;
      };
    };
}
