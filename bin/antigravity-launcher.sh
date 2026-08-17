#!/usr/bin/env bash
# Launcher script for Antigravity with single-instance and background service conflict protection

LOCKFILE="${XDG_RUNTIME_DIR:-/tmp}/antigravity-launcher.lock"

# Use file descriptor 200 for flock to prevent rapid multi-click race conditions
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    # Another launcher instance is currently starting up, exit cleanly
    exit 0
fi

# Check if antigravity process or service is already running (host or container)
if pgrep -f "opt/antigravity/antigravity" >/dev/null 2>&1 || \
   pgrep -f "antigravity-ide" >/dev/null 2>&1 || \
   pgrep -x "antigravity" >/dev/null 2>&1; then
    # Antigravity is already running. Focus existing window if using Sway.
    if command -v swaymsg >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then
        swaymsg '[app_id="(?i)antigravity"] focus' >/dev/null 2>&1 || \
        swaymsg '[class="(?i)antigravity"] focus' >/dev/null 2>&1 || \
        swaymsg '[title="(?i)antigravity"] focus' >/dev/null 2>&1
    fi
    exit 0
fi

# Launch Antigravity
if [ -x "$HOME/opt/antigravity/antigravity" ]; then
    exec "$HOME/opt/antigravity/antigravity" "$@"
elif [ -x "$HOME/.local/bin/antigravity" ]; then
    exec "$HOME/.local/bin/antigravity" "$@"
elif [ -x "/opt/antigravity/antigravity" ]; then
    exec "/opt/antigravity/antigravity" "$@"
else
    exec antigravity "$@"
fi
