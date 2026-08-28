#!/usr/bin/env bash
# Launcher script for Antigravity with Sway single-instance focus handling

# If Antigravity window is already open in Sway, bring it to focus
if command -v swaymsg >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then
    if swaymsg '[app_id="(?i)^antigravity$"] focus' >/dev/null 2>&1 || \
       swaymsg '[class="(?i)^antigravity$"] focus' >/dev/null 2>&1; then
        exit 0
    fi
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
