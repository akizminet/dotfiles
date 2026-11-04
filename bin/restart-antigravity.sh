#!/usr/bin/env bash
# Robust Antigravity Desktop Restart Script
# Safely restarts Antigravity even when invoked from inside an active Antigravity session.

set -euo pipefail

ANTIGRAVITY_BIN="${HOME}/opt/antigravity/antigravity"
LAUNCHER="${HOME}/dev/dotfiles/bin/antigravity-launcher.sh"
LOG_FILE="/tmp/antigravity-restart.log"

# If not already running inside detached systemd-run worker, detach immediately
if [ "${ANTIGRAVITY_RESTART_WORKER:-0}" != "1" ]; then
    echo "🚀 Handing off Antigravity restart to detached systemd user unit..."
    UNIT_NAME="antigravity-restart-$(date +%s)"
    systemd-run --user --unit="${UNIT_NAME}" \
        --setenv=ANTIGRAVITY_RESTART_WORKER=1 \
        --setenv=WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" \
        --setenv=DISPLAY="${DISPLAY:-:0}" \
        --setenv=XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}" \
        --setenv=PATH="${PATH}" \
        "$0" "${@}" >/dev/null 2>&1
    echo "✅ Detached restart job spawned (${UNIT_NAME}). Antigravity will restart in ~2 seconds."
    exit 0
fi

# ==================== DETACHED WORKER PROCESS ====================
exec >> "${LOG_FILE}" 2>&1
echo "=========================================="
echo "Restart initiated at $(date)"

# 1. Wait briefly to allow the calling agent/conversation to finish and flush messages
echo "[1/4] Waiting 2 seconds for active conversation to cleanly flush..."
sleep 2

# 2. Gracefully terminate existing Antigravity desktop & language_server processes
echo "[2/4] Terminating existing Antigravity processes..."
pkill -TERM -f '[o]pt/antigravity/antigravity' || true
pkill -TERM -f '[o]pt/antigravity/resources/bin/language_server' || true

# 3. Wait for processes to exit (up to 6 seconds)
for i in {1..12}; do
    if ! pgrep -f '[o]pt/antigravity/antigravity' >/dev/null && \
       ! pgrep -f '[o]pt/antigravity/resources/bin/language_server' >/dev/null; then
        echo "All Antigravity processes exited cleanly."
        break
    fi
    sleep 0.5
done

# Force kill if any process is still lingering
if pgrep -f '[o]pt/antigravity/antigravity' >/dev/null || \
   pgrep -f '[o]pt/antigravity/resources/bin/language_server' >/dev/null; then
    echo "Force-killing remaining Antigravity processes..."
    pkill -9 -f '[o]pt/antigravity/antigravity' || true
    pkill -9 -f '[o]pt/antigravity/resources/bin/language_server' || true
fi

sleep 1

# 4. Launch new Antigravity instance
echo "[4/4] Launching Antigravity..."
if [ -x "${LAUNCHER}" ]; then
    # Bypass single-instance check in launcher since we just killed the old instance
    exec "${ANTIGRAVITY_BIN}" "$@"
elif [ -x "${ANTIGRAVITY_BIN}" ]; then
    exec "${ANTIGRAVITY_BIN}" "$@"
else
    echo "❌ Antigravity binary not found at ${ANTIGRAVITY_BIN}!" >&2
    exit 1
fi
