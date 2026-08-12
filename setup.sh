#!/usr/bin/env bash

# Exit on error
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Setting up dotfiles from: $DOTFILES_DIR"

# Ensure GNU stow is installed
if ! command -v stow >/dev/null 2>&1; then
    echo "❌ Error: GNU 'stow' is not installed."
    echo "   Install stow using your package manager:"
    echo "   - Arch Linux: sudo pacman -S stow"
    echo "   - Debian/Ubuntu: sudo apt install stow"
    echo "   - Fedora: sudo dnf install stow"
    exit 1
fi

# Ensure ~/.config directory exists
mkdir -p "$HOME/.config"

# List of config packages to link
PACKAGES=("sway" "waybar" "rofi" "foot" "gtk-3.0" "fcitx5")

cd "$DOTFILES_DIR"

for pkg in "${PACKAGES[@]}"; do
    if [ -d "$pkg" ]; then
        echo "🔗 Linking $pkg..."
        stow -R "$pkg"
    else
        echo "⚠️ Warning: Package '$pkg' not found in $DOTFILES_DIR, skipping."
    fi
done

echo "✅ All dotfiles successfully linked!"
