#!/usr/bin/env bash

# Ensure screen powers on when swaylock unlocks/exits
trap 'swaymsg "output * dpms on"' EXIT

# Start swaylock in background and capture PID
swaylock -c 1e1e2e &
LOCK_PID=$!

# Turn off display 5 seconds after locking if still locked
(
    sleep 5
    if kill -0 "$LOCK_PID" 2>/dev/null; then
        swaymsg "output * dpms off"
    fi
) &

# Wait for swaylock to finish so trap fires on exit
wait "$LOCK_PID"
