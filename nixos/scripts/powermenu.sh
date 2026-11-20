#!/usr/bin/env bash

# Rofi Powermenu styled with Catppuccin Mocha theme

lock="🔒 Lock"
logout="🚪 Logout"
suspend="💤 Suspend"
reboot="🔄 Reboot"
shutdown="⚡ Shutdown"

options="$lock\n$logout\n$suspend\n$reboot\n$shutdown"

chosen=$(echo -e "$options" | rofi -dmenu -i -p " ⚡ Power " -theme "@rofiTheme@" -theme-str '
window {
    width: 350px;
    height: 340px;
}
listview {
    lines: 5;
}
')

case "$chosen" in
    "$lock")
        if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
            hyprlock
        else
            sway-lock
        fi
        ;;
    "$logout")
        if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
            hyprctl dispatch exit 2>/dev/null || loginctl terminate-user "$USER"
        else
            swaymsg exit 2>/dev/null || loginctl terminate-user "$USER"
        fi
        ;;
    "$suspend")
        systemctl suspend
        ;;
    "$reboot")
        systemctl reboot
        ;;
    "$shutdown")
        systemctl poweroff
        ;;
esac
