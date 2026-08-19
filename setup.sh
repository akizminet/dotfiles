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

# Setup individual user bin scripts and desktop files without overriding existing directories
echo "🔗 Setting up Antigravity launcher script and desktop entry..."
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"

if [ -f "$DOTFILES_DIR/bin/antigravity-launcher.sh" ]; then
    ln -sf "$DOTFILES_DIR/bin/antigravity-launcher.sh" "$HOME/.local/bin/antigravity-launcher.sh"
    chmod +x "$DOTFILES_DIR/bin/antigravity-launcher.sh" "$HOME/.local/bin/antigravity-launcher.sh"
fi

if [ -f "$DOTFILES_DIR/bin/google-chrome" ]; then
    echo "🔗 Linking google-chrome wrapper -> $HOME/.local/bin/google-chrome"
    ln -sf "$DOTFILES_DIR/bin/google-chrome" "$HOME/.local/bin/google-chrome"
    ln -sf "$DOTFILES_DIR/bin/google-chrome" "$HOME/.local/bin/google-chrome-stable"
    chmod +x "$DOTFILES_DIR/bin/google-chrome"
fi

if [ -f "$DOTFILES_DIR/applications/antigravity.desktop" ]; then
    ln -sf "$DOTFILES_DIR/applications/antigravity.desktop" "$HOME/.local/share/applications/antigravity.desktop"
fi

if [ -f "$DOTFILES_DIR/applications/google-chrome.desktop" ]; then
    echo "🔗 Linking google-chrome.desktop -> $HOME/.local/share/applications/google-chrome.desktop"
    ln -sf "$DOTFILES_DIR/applications/google-chrome.desktop" "$HOME/.local/share/applications/google-chrome.desktop"
fi

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

echo "✅ All dotfiles successfully linked!"
