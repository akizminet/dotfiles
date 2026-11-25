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
    fcitx5-lotus = {
      url = "github:LotusInputMethod/fcitx5-lotus";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, celluloid-src, akquick, fcitx5-lotus }:
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
        let envMachineId = builtins.getEnv "NIXOS_MACHINE_ID"; in
        if envMachineId == "none" then null
        else if envMachineId != "" then envMachineId
        else if builtins.pathExists /etc/machine-id then
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

      findLocalConfig = envVar: fileName:
        let
          candidates = [
            (builtins.getEnv envVar)
            "/etc/nixos/${fileName}"
            "/var/mnt/nixos/.rw-etc/upper/nixos/${fileName}"
            "/var/mnt/nixos/etc/nixos/${fileName}"
            "/mnt/.rw-etc/upper/nixos/${fileName}"
            "/mnt/etc/nixos/${fileName}"
          ];
        in
        lib.findFirst
          (p: p != "" && builtins.pathExists p)
          null
          candidates;

      hardwareConfigPath = findLocalConfig "NIXOS_HARDWARE_CONFIG" "hardware-configuration.nix";
      localHostsPath = findLocalConfig "NIXOS_LOCAL_HOSTS" "local-hosts.nix";

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
            fcitx5-lotus.nixosModules.fcitx5-lotus
            ./nixos/modules/base.nix
            ./nixos/modules/desktop-configs.nix
            ./nixos/modules/user-services.nix
            ./nixos/modules/user-packages.nix
            ./nixos/modules/external-apps.nix
          ]
          ++ lib.optional (hardwareConfigPath != null) hardwareConfigPath
          ++ lib.optional (localHostsPath != null) localHostsPath;
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
