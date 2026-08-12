#!/usr/bin/env bash

# Exit on error
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.config"

echo "🚀 Setting up dotfiles from: $DOTFILES_DIR"

# Ensure ~/.config directory exists
mkdir -p "$TARGET_DIR"

# List of top-level config packages to link directly into ~/.config/
PACKAGES=("sway" "waybar" "rofi" "foot" "gtk-3.0" "fcitx5" "flameshot" "autostart" "systemd")

for pkg in "${PACKAGES[@]}"; do
    pkg_dir="$DOTFILES_DIR/$pkg"
    if [ -d "$pkg_dir" ]; then
        target="$TARGET_DIR/$pkg"
        echo "🔗 Linking $pkg -> $target"
        rm -rf "$target"
        ln -s "$pkg_dir" "$target"
    else
        echo "⚠️ Warning: '$pkg' not found in $DOTFILES_DIR, skipping."
    fi
done

echo "✅ All dotfiles successfully linked!"
