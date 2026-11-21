#!/usr/bin/env bash

set -euo pipefail

has_backlight() {
    local entries=(/sys/class/backlight/*)
    [ -e "${entries[0]}" ]
}

case "${1:-}" in
    dim)
        if has_backlight; then
            exec brightnessctl -c backlight -s set 10
        else
            exec hyprctl hyprsunset gamma 40
        fi
        ;;
    restore)
        if has_backlight; then
            exec brightnessctl -c backlight -r
        else
            exec hyprctl hyprsunset gamma 100
        fi
        ;;
    *)
        echo "Usage: hypr-dim {dim|restore}" >&2
        exit 1
        ;;
esac
