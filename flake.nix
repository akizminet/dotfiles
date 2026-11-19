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
      lib = nixpkgs.lib;

      rawHost =
        let envHost = builtins.getEnv "NIXOS_HOSTNAME"; in
        if envHost != "" then envHost
        else if builtins.pathExists /etc/hostname then lib.strings.trim (builtins.readFile /etc/hostname)
        else "workstation";
      hostName = if rawHost != "" then rawHost else "workstation";

      rawUser =
        let sudoUser = builtins.getEnv "SUDO_USER"; in
        if sudoUser != "" && sudoUser != "root" then sudoUser
        else
          let envUser = builtins.getEnv "USER"; in
          if envUser != "" && envUser != "root" then envUser
          else "phamnv";
      username = rawUser;

      dotfilesDir =
        let envDir = builtins.getEnv "DOTFILES_DIR"; in
        if envDir != "" then envDir else "/home/${username}/dev/dotfiles";

      machineId =
        if builtins.pathExists /etc/machine-id then
          lib.strings.trim (builtins.readFile /etc/machine-id)
        else
          null;

      passwordHashPath = "/var/lib/nixos/${username}-password-hash";
      hasPasswordHash = builtins.any builtins.pathExists [
        passwordHashPath
        "/var/mnt/nixos${passwordHashPath}"
        "/mnt${passwordHashPath}"
      ];
      hashedPasswordFile = if hasPasswordHash then passwordHashPath else null;

      hardwareConfigCandidates = [
        (builtins.getEnv "NIXOS_HARDWARE_CONFIG")
        "/etc/nixos/hardware-configuration.nix"
        "/var/mnt/nixos/.rw-etc/upper/nixos/hardware-configuration.nix"
        "/var/mnt/nixos/etc/nixos/hardware-configuration.nix"
        "/mnt/.rw-etc/upper/nixos/hardware-configuration.nix"
        "/mnt/etc/nixos/hardware-configuration.nix"
      ];
      hardwareConfigPath = lib.findFirst
        (p: p != "" && builtins.pathExists p)
        null
        hardwareConfigCandidates;

      mkSystem = targetHostName:
        let
          hostSpec = {
            hostName = targetHostName;
            system = "x86_64-linux";
            inherit username dotfilesDir machineId hashedPasswordFile;
          };
        in
        lib.nixosSystem {
          system = hostSpec.system;
          specialArgs = {
            inherit self celluloid-src akquick hostSpec;
          };
          modules = [
            { nixpkgs.overlays = [ (final: prev: { pcre = prev.pcre2; }) ]; }
            ./nixos/modules/base.nix
            ./nixos/modules/user-packages.nix
            ./nixos/modules/external-apps.nix
          ] ++ lib.optional (hardwareConfigPath != null) hardwareConfigPath;
        };
    in
    {
      nixosConfigurations = {
        default = mkSystem hostName;
        workstation = mkSystem "workstation";
      } // {
        ${hostName} = mkSystem hostName;
      };
    };
}
