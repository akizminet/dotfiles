#!/usr/bin/env bash

set -u

MANUAL_LOCK=false
if [[ "${1:-}" == "--manual" ]]; then
    MANUAL_LOCK=true
fi

# Do not create multiple lockers when swayidle receives more than one event
if pgrep -xu "$USER" -x swaylock >/dev/null 2>&1; then
    exit 0
fi

if "$MANUAL_LOCK"; then
    # Use a dedicated idle timer for manual lock.
    swayidle -w \
        timeout 5 'swaymsg "output * dpms off"' \
        resume 'swaymsg "output * dpms on"' &
    IDLE_PID=$!

    swaylock -c 1e1e2e -F

    if [[ -n "${IDLE_PID:-}" ]]; then
        kill "$IDLE_PID" 2>/dev/null || true
    fi
    swaymsg 'output * dpms on' >/dev/null 2>&1 || true
    exit 0
fi

# -f returns once swaylock has locked the session, which lets swayidle -w
# finish its before-sleep command without waiting for the password entry.
exec swaylock -f -c 1e1e2e -F

