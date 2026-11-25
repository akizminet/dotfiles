# Dotfiles

**English** | [Tiếng Việt](README.vi.md)

Portable NixOS Flake configuration for a **Hyprland** workstation, with no hardcoded hostnames, UUIDs, or disk labels in Git, keeping `/etc` immutable via overlay.

## Structure

- `flake.nix`: Reads local machine config during evaluation (`--impure`) from `/etc/hostname` (or `NIXOS_HOSTNAME`), `/etc/machine-id`, `/etc/nixos/hardware-configuration.nix`, optional `/etc/nixos/local-hosts.nix`, and `/var/lib/nixos/<user>-password-hash`.
- `nixos/modules/`:
  - `base.nix`: Base OS, bootloader, network/VPN, Hyprland, `fcitx5`, `nh` wrapper.
  - `desktop-configs.nix`: Desktop configs (`hypr`, `ironbar`, `rofi`, `foot`, `satty`, `swaync`, `fcitx5`) and scripts.
  - `user-packages.nix`: GUI & CLI dev tools.
  - `user-services.nix`: Systemd user services/targets.
  - `external-apps.nix`: External app manager (`external-apps`).

## Usage

```bash
# Apply changes (nh wrapper already passes --impure)
nh os switch

# Update and apply
git pull --ff-only && nh os switch
```

## New Machine Setup

```bash
sudo mkdir -p /mnt/.rw-etc/upper/nixos
sudo nixos-generate-config --root /mnt --show-hardware-config | sudo tee /mnt/.rw-etc/upper/nixos/hardware-configuration.nix >/dev/null
sudo NIXOS_HOSTNAME="my-host" nixos-install --flake ~/dev/dotfiles#default --impure --root /mnt
```
