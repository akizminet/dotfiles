#!/usr/bin/env bash

set -euo pipefail

# Do not create multiple lockers when swaylock is already running
if pgrep -xu "$USER" -x swaylock >/dev/null 2>&1; then
    exit 0
fi

WALLPAPER="$HOME/.config/sway/wallpapers/ghibli-midnight-station.jpg"

LOCK_ARGS=(
    -f
    -F
    --indicator-radius 100
    --indicator-thickness 7
    --inside-color 1e1e2ecc
    --ring-color cba6f7
    --key-hl-color 89b4fa
    --bs-hl-color f38ba8
    --line-color 00000000
    --text-color cdd6f4
    --inside-ver-color 89b4fa88
    --ring-ver-color 89b4fa
    --inside-wrong-color f38ba888
    --ring-wrong-color f38ba8
    --inside-clear-color a6e3a188
    --ring-clear-color a6e3a1
)

# -f returns once swaylock has locked the session, which lets swayidle -w
# finish its before-sleep command without waiting for the password entry.
if [ -f "$WALLPAPER" ]; then
    exec swaylock "${LOCK_ARGS[@]}" -i "$WALLPAPER" -s fill
else
    exec swaylock "${LOCK_ARGS[@]}" -c 1e1e2e
fi


