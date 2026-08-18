#!/usr/bin/env bash
# Dynamic Day/Night Wallpaper Switcher for Sway (Pure Bash + awk)

set -euo pipefail

WALLPAPER_DIR="/var/home/phamnv/.config/sway/wallpapers"
DAY_WALLPAPER="${WALLPAPER_DIR}/ghibli-day-station.jpg"
NIGHT_WALLPAPER="${WALLPAPER_DIR}/ghibli-midnight-station.jpg"
STATE_FILE="/tmp/sway_wallpaper_mode_${UID}"

# Coordinates for Vietnam (Ho Chi Minh City / Hanoi approx: 10.82N, 106.63E)
LAT="10.8231"
LON="106.6297"

# Ensure SWAYSOCK is available even when called from systemd user timer
if [[ -z "${SWAYSOCK:-}" ]]; then
    SWAY_SOCKET=$(find "/run/user/${UID}" -maxdepth 1 -name "sway-ipc.*.sock" 2>/dev/null | head -n 1)
    if [[ -n "${SWAY_SOCKET}" ]]; then
        export SWAYSOCK="${SWAY_SOCKET}"
    fi
fi

apply_wallpaper() {
    local mode="$1"
    local wallpaper="$2"
    if command -v swaymsg >/dev/null 2>&1; then
        swaymsg "output * bg '${wallpaper}' fill" >/dev/null 2>&1 || true
        echo "${mode}" > "${STATE_FILE}"
        echo "Applied ${mode} wallpaper: ${wallpaper}"
    fi
}

calc_solar_mode() {
    awk -v lat="${LAT}" -v lon="${LON}" '
    BEGIN {
        pi = 3.14159265358979323846;
        rad = pi / 180.0;
        
        "date +%j" | getline n;
        "date +%:z" | getline tz_str;
        split(tz_str, tz_parts, ":");
        tz_offset = tz_parts[1] + (tz_parts[2] / 60.0);
        
        lng_hour = lon / 15.0;
        
        for (is_rise = 1; is_rise >= 0; is_rise--) {
            t = n + ((is_rise ? 6 : 18) - lng_hour) / 24.0;
            M = (0.9856 * t) - 3.289;
            L = (M + (1.916 * sin(M * rad)) + (0.020 * sin(2 * M * rad)) + 282.634) % 360;
            if (L < 0) L += 360;
            
            RA = (atan2(0.91764 * sin(L * rad), cos(L * rad)) / rad) % 360;
            if (RA < 0) RA += 360;
            
            L_quad = int(L / 90.0) * 90;
            RA_quad = int(RA / 90.0) * 90;
            RA = (RA + (L_quad - RA_quad)) / 15.0;
            
            sinDec = 0.39782 * sin(L * rad);
            cosDec = cos(atan2(sinDec, sqrt(1 - sinDec^2)));
            cosH = (cos(90.833 * rad) - (sinDec * sin(lat * rad))) / (cosDec * cos(lat * rad));
            
            if (cosH > 1 || cosH < -1) continue;
            
            H = (is_rise ? (360 - (atan2(sqrt(1 - cosH^2), cosH) / rad)) : (atan2(sqrt(1 - cosH^2), cosH) / rad)) / 15.0;
            T = H + RA - (0.06571 * t) - 6.622;
            UT = (T - lng_hour) % 24;
            if (UT < 0) UT += 24;
            
            local_h = (UT + tz_offset) % 24;
            if (local_h < 0) local_h += 24;
            
            total_minutes = int(local_h * 60);
            if (is_rise) rise_min = total_minutes;
            else set_min = total_minutes;
        }
        
        "date +%H" | getline cur_h;
        "date +%M" | getline cur_m;
        cur_min = cur_h * 60 + cur_m;
        
        if (cur_min >= rise_min && cur_min < set_min) {
            print "day";
        } else {
            print "night";
        }
    }'
}

ACTION="${1:-auto}"

case "${ACTION}" in
    day)
        apply_wallpaper "day" "${DAY_WALLPAPER}"
        ;;
    night)
        apply_wallpaper "night" "${NIGHT_WALLPAPER}"
        ;;
    toggle)
        CURRENT_MODE=$(cat "${STATE_FILE}" 2>/dev/null || echo "day")
        if [[ "${CURRENT_MODE}" == "day" ]]; then
            apply_wallpaper "night" "${NIGHT_WALLPAPER}"
        else
            apply_wallpaper "day" "${DAY_WALLPAPER}"
        fi
        ;;
    test)
        echo "Testing transition: Switching to NIGHT in 1s..."
        apply_wallpaper "night" "${NIGHT_WALLPAPER}"
        sleep 2
        echo "Testing transition: Switching to DAY in 2s..."
        apply_wallpaper "day" "${DAY_WALLPAPER}"
        ;;
    --force)
        MODE=$(calc_solar_mode)
        if [[ "${MODE}" == "night" ]]; then
            apply_wallpaper "night" "${NIGHT_WALLPAPER}"
        else
            apply_wallpaper "day" "${DAY_WALLPAPER}"
        fi
        ;;
    auto|*)
        MODE=$(calc_solar_mode)
        TARGET_WALLPAPER="${DAY_WALLPAPER}"
        if [[ "${MODE}" == "night" ]]; then
            TARGET_WALLPAPER="${NIGHT_WALLPAPER}"
        fi

        # Check if already in this mode
        if [[ -f "${STATE_FILE}" ]]; then
            CURRENT_MODE=$(cat "${STATE_FILE}" 2>/dev/null || true)
            if [[ "${CURRENT_MODE}" == "${MODE}" ]]; then
                exit 0
            fi
        fi

        apply_wallpaper "${MODE}" "${TARGET_WALLPAPER}"
        ;;
esac
