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
      fcitx5WithAddons = pkgs.kdePackages.fcitx5-with-addons.override {
        addons = [
          pkgs.kdePackages.fcitx5-unikey
          pkgs.kdePackages.fcitx5-configtool
          pkgs.fcitx5-gtk
          pkgs.fcitx5-bamboo
        ];
      };
    in
    {
      packages.${system} = {
        default = pkgs.buildEnv {
          name = "default-profile";
          paths = [
            # GUI & Desktop Applications
            pkgs.google-chrome
            pkgs.libreoffice
            pkgs.flameshot

            # CLI & Network Tools
            pkgs.ffmpeg-full
            pkgs.gh
            pkgs.tailscale
            pkgs.wayvnc
            pkgs.zapret

            # Input Method & Addons
            fcitx5WithAddons

            # Fonts
            pkgs.nerd-fonts.monaspace

            # GPU wrapper
            nixGLIntel
          ];
        };

        fcitx5 = fcitx5WithAddons;
        fcitx5-with-addons = fcitx5WithAddons;
      };
    };
}
