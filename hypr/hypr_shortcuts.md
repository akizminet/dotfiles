# Hyprland Keyboard Shortcuts Reference

> **Modifier Key (`$mainMod`):** `SUPER` / `Windows Key`

---

## 🚀 Basics & System Controls

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `SUPER + Return` | **Open Terminal** | Spawns `foot` terminal emulator |
| `SUPER + d` | **Application Launcher** | Opens `rofi` run/drun menu |
| `SUPER + q` | **Kill Window** | Closes the focused window |
| `SUPER + Shift + e` | **Exit Hyprland** | Exits the Hyprland Wayland session |
| `SUPER + v` | **Toggle Floating** | Toggles window between tiling & floating |
| `SUPER + f` | **Fullscreen** | Toggles fullscreen mode for active window |
| `SUPER + n` | **Notification Center** | Opens/closes SwayNC notification panel |
| `SUPER + L` | **Lock Screen** | Locks the screen with `hyprlock` |
| `SUPER + Shift + L` | **Screen Off (DPMS)** | Turns off monitor displays |
| `SUPER + Mouse Left` | **Drag Window** | Move floating container dynamically |
| `SUPER + Mouse Right` | **Resize Window** | Resize container dynamically |

---

## 🎯 Navigation & Window Focus

| Shortcut | Action |
| :--- | :--- |
| `SUPER + Left` / `SUPER + h` | Focus Left |
| `SUPER + Down` / `SUPER + j` | Focus Down |
| `SUPER + Up` / `SUPER + k` | Focus Up |
| `SUPER + Right` / `SUPER + l` | Focus Right |

---

## 🚚 Window Movement

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `SUPER + Shift + Left` / `SUPER + Shift + h` | Move window Left | Moves window left (group-aware: merges in / pops out) |
| `SUPER + Shift + Down` / `SUPER + Shift + j` | Move window Down | Moves window down (group-aware: merges in / pops out) |
| `SUPER + Shift + Up` / `SUPER + Shift + k` | Move window Up | Moves window up (group-aware: merges in / pops out) |
| `SUPER + Shift + Right` / `SUPER + Shift + l` | Move window Right | Moves window right (group-aware: merges in / pops out) |

---

## 📑 Window Groups (Tabbed / Stacked)

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `SUPER + g` | **Toggle Group** | Turns focused window into a group or dissolves it |
| `SUPER + Shift + g` | **Lock Group** | Locks active group from automatically accepting windows |
| `SUPER + Tab` | **Next Tab** | Switch to the next window in the group |
| `SUPER + Shift + Tab` | **Previous Tab** | Switch to the previous window in the group |
| `SUPER + Ctrl + Left` / `SUPER + Ctrl + h` | **Move Tab Left** | Reorder current window tab to the left |
| `SUPER + Ctrl + Right` / `SUPER + Ctrl + l` | **Move Tab Right** | Reorder current window tab to the right |

---

## 🖥️ Workspaces

| Shortcut | Action |
| :--- | :--- |
| `SUPER + 1` ... `SUPER + 9` | Switch to Workspace `1` through `9` |
| `SUPER + Shift + 1` ... `SUPER + Shift + 9` | Move focused window to Workspace `1` through `9` |

---

## 📸 Screenshots (via Satty)

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `Print` / `SUPER + Shift + s` | **Satty Region** | Interactive screenshot region selection |
| `Shift + Print` | **Full Screen to Clipboard** | Capture entire screen directly to clipboard |
| `Ctrl + Print` | **Delayed Screenshot** | Capture region after 2-second delay |

---

## 🔊 Audio & Volume Controls (WirePlumber / PipeWire)

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `XF86AudioRaiseVolume` | **Volume Up** | Increases volume (+5%) via `wpctl` |
| `XF86AudioLowerVolume` | **Volume Down** | Decreases volume (-5%) via `wpctl` |
| `XF86AudioMute` | **Toggle Audio Mute** | Mutes/unmutes audio output |
| `XF86AudioMicMute` | **Toggle Mic Mute** | Mutes/unmutes microphone input |
