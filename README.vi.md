# Dotfiles

[English](README.md) | **Tiếng Việt**

Cấu hình NixOS Flake di động cho workstation chạy **Hyprland**, không hardcode hostname, UUID hay label ổ đĩa trong Git và giữ `/etc` immutable qua overlay.

## Cấu trúc

- `flake.nix`: Đọc cấu hình local lúc evaluate (`--impure`) từ `/etc/hostname` (hoặc `NIXOS_HOSTNAME`), `/etc/machine-id`, `/etc/nixos/hardware-configuration.nix`, `/etc/nixos/local-hosts.nix` (tuỳ chọn) và `/var/lib/nixos/<user>-password-hash`.
- `nixos/modules/`:
  - `base.nix`: Base OS, bootloader, network/VPN, Hyprland, `fcitx5`, `nh` wrapper.
  - `desktop-configs.nix`: Cấu hình desktop (`hypr`, `ironbar`, `rofi`, `foot`, `satty`, `swaync`, `fcitx5`) và scripts.
  - `user-packages.nix`: Gói GUI & CLI dev tools.
  - `user-services.nix`: Systemd user services/targets.
  - `external-apps.nix`: Quản lý app ngoài nixpkgs (`external-apps`).

## Sử dụng

```bash
# Áp dụng thay đổi (nh đã bọc sẵn --impure)
nh os switch

# Cập nhật và áp dụng
git pull --ff-only && nh os switch
```

## Cài máy mới

```bash
sudo mkdir -p /mnt/.rw-etc/upper/nixos
sudo nixos-generate-config --root /mnt --show-hardware-config | sudo tee /mnt/.rw-etc/upper/nixos/hardware-configuration.nix >/dev/null
sudo NIXOS_HOSTNAME="my-host" nixos-install --flake ~/dev/dotfiles#default --impure --root /mnt
```
