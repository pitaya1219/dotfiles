#!/usr/bin/env bash

# Notification abstraction layer
# Sends notifications using platform-specific methods

set -euo pipefail

# Detect platform
detect_platform() {
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "macos"
    elif [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d /data/data/com.termux ]]; then
        echo "termux"
    elif grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl2"
    elif [[ -f /etc/os-release ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

# Send notification
# Usage: notify "title" "message" ["priority"]
# Priority: low, normal, high (default: normal)
notify() {
    local title="$1"
    local message="$2"
    local priority="${3:-normal}"
    local platform="$(detect_platform)"

    case "$platform" in
        macos)
            # Use osascript for macOS notifications
            osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
            ;;
        termux)
            # Use termux-notification
            if command -v termux-notification &>/dev/null; then
                local urgency="default"
                case "$priority" in
                    high) urgency="high" ;;
                    low) urgency="low" ;;
                esac
                termux-notification --title "$title" --content "$message" --priority "$urgency" 2>/dev/null || true
            fi
            ;;
        linux|wsl2)
            # Use notify-send if available
            if command -v notify-send &>/dev/null; then
                local urgency="normal"
                case "$priority" in
                    high) urgency="critical" ;;
                    low) urgency="low" ;;
                esac
                notify-send -u "$urgency" "$title" "$message" 2>/dev/null || true
            fi
            ;;
    esac
}

# If run directly, use arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 <title> <message> [priority]"
        echo "Priority: low, normal, high (default: normal)"
        exit 1
    fi
    notify "$@"
fi
