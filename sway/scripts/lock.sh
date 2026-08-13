#!/usr/bin/env bash

set -u

MANUAL_LOCK=false
if [[ "${1:-}" == "--manual" ]]; then
    MANUAL_LOCK=true
fi

# Do not create multiple lockers when swayidle receives more than one event
# (for example, before-sleep and lock during suspend).
if pgrep -xu "$USER" -x swaylock >/dev/null 2>&1; then
    exit 0
fi

# A lock request must always be visible, including after a resume event.
swaymsg 'output * power on' >/dev/null 2>&1 || true

if "$MANUAL_LOCK"; then
    # Use a dedicated idle timer for manual lock. Its resume event is what
    # powers the display back on when the first key wakes the screen.
    swayidle \
        timeout 10 'swaymsg "output * power off"' \
        resume 'swaymsg "output * power on"' &
    IDLE_PID=$!

    swaylock -c 1e1e2e -F &
    LOCK_PID=$!

    cleanup() {
        if [[ -n "${IDLE_PID:-}" ]]; then
            kill "$IDLE_PID" 2>/dev/null || true
        fi
        swaymsg 'output * power on' >/dev/null 2>&1 || true
    }
    trap cleanup EXIT

    wait "$LOCK_PID"
    exit 0
fi

# -f returns once swaylock has locked the session, which lets swayidle -w
# finish its before-sleep command without waiting for the password entry.
exec swaylock -f -c 1e1e2e -F
