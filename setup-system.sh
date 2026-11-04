#!/usr/bin/env bash
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🛡️ Installing SELinux policy for Nix store execution..."
sudo semodule -i "$DOTFILES_DIR/selinux/nix_store_exec.cil"

echo "🔗 Setting up system symlinks in /usr/local/bin..."
sudo mkdir -p /usr/local/bin
sudo ln -sfn /nix/var/nix/profiles/default/bin/zapret /usr/local/bin/zapret
sudo ln -sfn /nix/var/nix/profiles/default/bin/openvpn /usr/local/bin/openvpn

if [ -f "$DOTFILES_DIR/systemd/system/zapret.service" ]; then
    echo "⚙️ Installing systemd zapret.service..."
    sudo cp "$DOTFILES_DIR/systemd/system/zapret.service" /etc/systemd/system/zapret.service
    sudo restorecon -v /etc/systemd/system/zapret.service
    sudo systemctl daemon-reload
fi

echo "✅ System setup completed!"
