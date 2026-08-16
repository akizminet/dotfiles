#!/usr/bin/env bash

set -euo pipefail

# Kill any existing swayidle instance for this user
pkill -xu "$USER" -x swayidle 2>/dev/null || true
sleep 0.2

LOCK_CMD="$HOME/.config/sway/scripts/lock.sh"
LOG_FILE="$HOME/.cache/swayidle.log"

exec swayidle -d -w \
    timeout 30 'if pgrep -xu "$USER" -x swaylock >/dev/null 2>&1; then swaymsg "output * dpms off"; fi' \
         resume 'swaymsg "output * dpms on"' \
    timeout 300 "$LOCK_CMD" \
    timeout 330 'swaymsg "output * dpms off"' \
         resume 'swaymsg "output * dpms on"' \
    before-sleep "$LOCK_CMD" \
    after-resume 'swaymsg "output * dpms on"' \
    lock "$LOCK_CMD" \
    unlock 'swaymsg "output * dpms on"' >> "$LOG_FILE" 2>&1

