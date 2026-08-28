{
  description = "Default user profile for Fedora Sway Atomic";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixgl.url = "github:nix-community/nixGL";
    nixgl.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixgl }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      nixGLIntel = nixgl.packages.${system}.nixGLIntel;
    in
    {
      packages.${system}.default = pkgs.buildEnv {
        name = "default-profile";
        paths = [
          # GUI & Desktop Applications
          pkgs.google-chrome
          pkgs.libreoffice
          pkgs.flameshot

          # CLI Tools
          pkgs.ffmpeg
          pkgs.gh
          pkgs.tailscale

          # Input Method & Addons
          (pkgs.kdePackages.fcitx5-with-addons.override {
            addons = [
              pkgs.kdePackages.fcitx5-unikey
              pkgs.kdePackages.fcitx5-configtool
              pkgs.fcitx5-gtk
            ];
          })

          # Fonts
          pkgs.nerd-fonts.monaspace

          # GPU wrapper
          nixGLIntel
        ];
      };
    };
}
