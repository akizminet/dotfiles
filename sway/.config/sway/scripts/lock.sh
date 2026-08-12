#!/usr/bin/env bash

# Start swaylock in background
swaylock -c 1e1e2e &

# Turn off display 5 seconds after locking if still locked
(
    sleep 5
    if pgrep -xu "$USER" swaylock >/dev/null; then
        swaymsg "output * dpms off"
    fi
) &
