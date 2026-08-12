#!/usr/bin/env bash

# Exit on error
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.config"

echo "🚀 Setting up dotfiles from: $DOTFILES_DIR"

# Ensure ~/.config directory exists
mkdir -p "$TARGET_DIR"

# List of config packages to link
PACKAGES=("sway" "waybar" "rofi" "foot" "gtk-3.0" "fcitx5")

for pkg in "${PACKAGES[@]}"; do
    pkg_config="$DOTFILES_DIR/$pkg/.config"
    if [ -d "$pkg_config" ]; then
        echo "🔗 Linking $pkg..."
        for item in "$pkg_config"/*; do
            [ -e "$item" ] || continue
            name="$(basename "$item")"
            target="$TARGET_DIR/$name"
            
            # Remove existing symlink or old item if present
            rm -rf "$target"
            
            # Create symbolic link pointing to dotfiles
            ln -s "$item" "$target"
            echo "   Linked $name -> $target"
        done
    else
        echo "⚠️ Warning: '$pkg/.config' not found in $DOTFILES_DIR, skipping."
    fi
done

echo "✅ All dotfiles successfully linked!"

