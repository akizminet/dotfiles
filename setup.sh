#!/usr/bin/env bash

# Exit on error
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.config"

echo "🚀 Setting up dotfiles from: $DOTFILES_DIR"

# Ensure ~/.config directory exists
mkdir -p "$TARGET_DIR"

# List of top-level config packages to link directly into ~/.config/
PACKAGES=("sway" "waybar" "rofi" "foot" "gtk-3.0" "fcitx5" "flameshot" "autostart" "systemd" "environment.d")

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

echo "🔗 Setting up desktop entries..."
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"

for script in "$DOTFILES_DIR/bin"/*; do
    if [ -f "$script" ]; then
        script_name="$(basename "$script")"
        echo "🔗 Linking $script -> $HOME/.local/bin/$script_name"
        ln -sf "$script" "$HOME/.local/bin/$script_name"
        chmod +x "$script" "$HOME/.local/bin/$script_name"
    fi
done

if [ -f "$DOTFILES_DIR/bin/google-chrome" ]; then
    ln -sf "$DOTFILES_DIR/bin/google-chrome" "$HOME/.local/bin/google-chrome-stable"
fi

for app in "$DOTFILES_DIR/applications"/*.desktop; do
    if [ -f "$app" ]; then
        echo "🔗 Linking $(basename "$app") -> $HOME/.local/share/applications/$(basename "$app")"
        ln -sf "$app" "$HOME/.local/share/applications/$(basename "$app")"
    fi
done

if [ -x "$HOME/opt/antigravity/antigravity" ]; then
    echo "🔗 Linking $HOME/opt/antigravity/antigravity -> $HOME/.local/bin/antigravity"
    ln -sf "$HOME/opt/antigravity/antigravity" "$HOME/.local/bin/antigravity"
fi

if [ -x "$HOME/.nix-profile/bin/flameshot" ]; then
    echo "🔗 Linking $HOME/.nix-profile/bin/flameshot -> $HOME/.local/bin/flameshot"
    ln -sf "$HOME/.nix-profile/bin/flameshot" "$HOME/.local/bin/flameshot"
fi

if [ -f "$DOTFILES_DIR/mimeapps.list" ]; then
    echo "🔗 Linking mimeapps.list -> $TARGET_DIR/mimeapps.list"
    ln -sf "$DOTFILES_DIR/mimeapps.list" "$TARGET_DIR/mimeapps.list"
fi

# Link host system fonts to ~/.local/share/fonts for Nix apps & containers
echo "🔗 Setting up fonts in ~/.local/share/fonts..."
mkdir -p "$HOME/.local/share/fonts"
if [ -d "/usr/share/fonts" ]; then
    ln -sfn "/usr/share/fonts" "$HOME/.local/share/fonts/system"
fi
if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true
fi

echo "✅ All dotfiles successfully linked!"
