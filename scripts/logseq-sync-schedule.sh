#!/usr/bin/env bash

set -euo pipefail

# Logseq Sync Scheduler Setup
# Configures automatic syncing based on platform

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/logseq-sync.sh"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# Detect platform
detect_platform() {
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "macos"
    elif [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d /data/data/com.termux ]]; then
        echo "termux"
    elif grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl2"
    elif [[ -f /etc/os-release ]]; then
        echo "ubuntu"
    else
        echo "unknown"
    fi
}

# Setup macOS launchd
setup_macos() {
    log_info "Setting up macOS launchd agent..."

    local LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
    local PLIST_FILE="$LAUNCH_AGENTS_DIR/com.logseq.sync.plist"

    mkdir -p "$LAUNCH_AGENTS_DIR"

    # Create launchd plist
    cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.logseq.sync</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SYNC_SCRIPT</string>
        <string>bidirectional</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>LOGSEQ_LOCAL</key>
        <string>${LOGSEQ_LOCAL:-$HOME/logseq}</string>
        <key>LOGSEQ_REMOTE</key>
        <string>${LOGSEQ_REMOTE:-pcloud-crypt:/logseq}</string>
    </dict>
    <key>StartInterval</key>
    <integer>1800</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.local/share/logseq-sync.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.local/share/logseq-sync-error.log</string>
</dict>
</plist>
EOF

    # Load the agent
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    launchctl load "$PLIST_FILE"

    log_info "macOS launchd agent loaded (every 30 minutes)"
}

# Setup Termux scheduling
setup_termux() {
    log_info "Setting up Termux service..."

    # Check if termux-services is available
    if ! command -v sv &>/dev/null; then
        log_error "termux-services not found. Install it first:"
        echo "  pkg install termux-services"
        echo "  After installation, restart Termux"
        exit 1
    fi

    # Detect service directory based on sv location
    local SV_PATH="$(dirname "$(dirname "$(command -v sv)")")"
    local SVDIR="${SVDIR:-$SV_PATH/var/service}"
    local SERVICE_DIR="$SVDIR/logseq-sync"
    mkdir -p "$SERVICE_DIR"

    # Get sync interval (default 30 minutes = 1800 seconds)
    local SYNC_INTERVAL="${LOGSEQ_SYNC_INTERVAL:-1800}"

    # Get the dotfiles directory (assume schedule script is in dotfiles/scripts/)
    local DOTFILES_SCRIPT="${DOTFILES_DIR:-\$HOME/dotfiles}/scripts/logseq-sync.sh"
    local DOTFILES_NOTIFY="${DOTFILES_DIR:-\$HOME/dotfiles}/scripts/notify.sh"
    local NOTIFY_WRAPPER_PATH="$PREFIX/bin/logseq-notify"

    cat > "$SERVICE_DIR/run" <<RUNEOF
#!/data/data/com.termux/files/usr/bin/bash
exec 2>&1

export LOGSEQ_LOCAL="${LOGSEQ_LOCAL:-\$HOME/storage/shared/logseq}"
export LOGSEQ_REMOTE="${LOGSEQ_REMOTE:-pcloud-crypt:/logseq}"
export RCLONE_BIN="/data/data/com.termux/files/usr/bin/rclone-secure"

# Create notify wrapper
NOTIFY_WRAPPER="$NOTIFY_WRAPPER_PATH"
sed '1s|^#!/usr/bin/env bash\$|#!/data/data/com.termux/files/usr/bin/bash|' $DOTFILES_NOTIFY > \$NOTIFY_WRAPPER
chmod +x \$NOTIFY_WRAPPER
export NOTIFY_SCRIPT="\$NOTIFY_WRAPPER"

while true; do
    echo "Starting Logseq sync..."
    if bash <(sed '1s|^#!/usr/bin/env bash\$|#!/data/data/com.termux/files/usr/bin/bash|' $DOTFILES_SCRIPT) bidirectional; then
        echo "Sync completed successfully. Sleeping for $SYNC_INTERVAL seconds..."
    else
        echo "Sync failed (exit \$?). Sleeping for $SYNC_INTERVAL seconds before retry..."
    fi
    sleep $SYNC_INTERVAL
done
RUNEOF
    chmod +x "$SERVICE_DIR/run"

    # Create log directory
    mkdir -p "$SERVICE_DIR/log/main"
    cat > "$SERVICE_DIR/log/run" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
exec svlogd -tt ./main
EOF
    chmod +x "$SERVICE_DIR/log/run"

    # Start service (with SVDIR set)
    export SVDIR
    rm -f "$SERVICE_DIR/down"

    # Need to restart runsvdir to pick up new service
    log_info "Restarting service daemon..."
    sv-enable logseq-sync

    # Give it a moment to initialize
    sleep 2

    local INTERVAL_MIN=$((SYNC_INTERVAL / 60))
    log_info "Termux service enabled (every $INTERVAL_MIN minutes)"
    sv status logseq-sync 2>/dev/null || log_warn "Service starting up..."

    # Setup Termux:Boot script to start on device boot
    local BOOT_DIR="$HOME/.termux/boot"
    mkdir -p "$BOOT_DIR"

    cat > "$BOOT_DIR/logseq-sync.sh" <<'BOOTEOF'
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock
sv-enable logseq-sync
BOOTEOF
    chmod +x "$BOOT_DIR/logseq-sync.sh"

    echo ""
    log_info "Termux:Boot script created at $BOOT_DIR/logseq-sync.sh"
    echo ""
    log_warn "To keep service running after closing Termux:"
    echo "   1. Install Termux:Boot app from F-Droid"
    echo "   2. Open Termux:Boot once to enable it"
    echo "   3. Disable battery optimization for Termux in Android settings"
    echo "   4. Reboot device or run: termux-wake-lock && sv-enable logseq-sync"
}

# Setup systemd timer (Ubuntu/WSL2)
setup_systemd() {
    log_info "Setting up systemd timer..."

    local USER_SYSTEMD_DIR="$HOME/.config/systemd/user"
    mkdir -p "$USER_SYSTEMD_DIR"

    # Create service file
    cat > "$USER_SYSTEMD_DIR/logseq-sync.service" <<EOF
[Unit]
Description=Logseq Cloud Sync
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment="LOGSEQ_LOCAL=${LOGSEQ_LOCAL:-$HOME/logseq}"
Environment="LOGSEQ_REMOTE=${LOGSEQ_REMOTE:-pcloud-crypt:/logseq}"
ExecStart=$SYNC_SCRIPT bidirectional
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

    # Create timer file
    cat > "$USER_SYSTEMD_DIR/logseq-sync.timer" <<EOF
[Unit]
Description=Logseq Cloud Sync Timer
Requires=logseq-sync.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=30min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Reload systemd and enable timer
    systemctl --user daemon-reload
    systemctl --user enable logseq-sync.timer
    systemctl --user start logseq-sync.timer

    log_info "Systemd timer enabled (every 30 minutes)"
    systemctl --user status logseq-sync.timer --no-pager
}

# Setup cron (fallback)
setup_cron() {
    log_info "Setting up cron job..."

    # Add cron entry if not exists
    local CRON_ENTRY="*/30 * * * * $SYNC_SCRIPT bidirectional >/dev/null 2>&1"

    if crontab -l 2>/dev/null | grep -F "$SYNC_SCRIPT" &>/dev/null; then
        log_warn "Cron entry already exists"
    else
        (crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -
        log_info "Cron job added (every 30 minutes)"
    fi
}

# Remove scheduling
remove_scheduling() {
    local platform="$1"

    case "$platform" in
        macos)
            log_info "Removing macOS launchd agent..."
            local PLIST_FILE="$HOME/Library/LaunchAgents/com.logseq.sync.plist"
            if [[ -f "$PLIST_FILE" ]]; then
                launchctl unload "$PLIST_FILE" 2>/dev/null || true
                rm -f "$PLIST_FILE"
            fi
            ;;
        termux)
            log_info "Removing Termux service..."
            if command -v sv &>/dev/null; then
                local SV_PATH="$(dirname "$(dirname "$(command -v sv)")")"
                local SVDIR="${SVDIR:-$SV_PATH/var/service}"
                export SVDIR
                sv down logseq-sync 2>/dev/null || true
                rm -rf "$SVDIR/logseq-sync"
            fi

            # Remove Termux:Boot script
            local BOOT_SCRIPT="$HOME/.termux/boot/logseq-sync.sh"
            if [[ -f "$BOOT_SCRIPT" ]]; then
                rm -f "$BOOT_SCRIPT"
                log_info "Removed Termux:Boot script"
            fi

            # Release wakelock if held
            if command -v termux-wake-unlock &>/dev/null; then
                termux-wake-unlock 2>/dev/null || true
            fi
            ;;
        ubuntu|wsl2)
            if systemctl --user list-timers 2>/dev/null | grep -q logseq-sync; then
                log_info "Removing systemd timer..."
                systemctl --user stop logseq-sync.timer
                systemctl --user disable logseq-sync.timer
                rm -f "$HOME/.config/systemd/user/logseq-sync."{service,timer}
                systemctl --user daemon-reload
            else
                log_info "Removing cron job..."
                crontab -l 2>/dev/null | grep -vF "$SYNC_SCRIPT" | crontab - 2>/dev/null || true
            fi
            ;;
    esac

    log_info "Scheduling removed"
}

# Show status
show_status() {
    local platform="$1"

    echo "Platform: $platform"
    echo ""

    case "$platform" in
        macos)
            local PLIST_FILE="$HOME/Library/LaunchAgents/com.logseq.sync.plist"
            if [[ -f "$PLIST_FILE" ]] && launchctl list | grep -q com.logseq.sync; then
                log_info "macOS launchd agent active"
                launchctl list | grep com.logseq.sync
            else
                log_warn "No scheduling configured"
            fi
            ;;
        termux)
            if command -v sv &>/dev/null; then
                local SV_PATH="$(dirname "$(dirname "$(command -v sv)")")"
                local SVDIR="${SVDIR:-$SV_PATH/var/service}"
                export SVDIR
                log_info "Termux services:"
                sv status logseq-sync 2>/dev/null || log_warn "Service not configured"
            else
                log_error "termux-services not available"
            fi
            ;;
        ubuntu|wsl2)
            if systemctl --user list-timers 2>/dev/null | grep -q logseq-sync; then
                log_info "Systemd timer active:"
                systemctl --user list-timers logseq-sync.timer --no-pager
            elif crontab -l 2>/dev/null | grep -qF "$SYNC_SCRIPT"; then
                log_info "Cron job active:"
                crontab -l | grep -F "$SYNC_SCRIPT"
            else
                log_warn "No scheduling configured"
            fi
            ;;
    esac
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [command]

Setup automatic Logseq sync scheduling based on platform

Commands:
  setup     Setup automatic sync for current platform
  remove    Remove scheduling
  status    Show scheduling status
  help      Show this help

Platform Detection:
  - macOS: Uses launchd
  - Termux: Uses termux-services (sv)
  - Ubuntu/WSL2: Uses systemd timers or cron

EOF
}

# Main
main() {
    local platform
    platform="$(detect_platform)"

    local command="${1:-setup}"

    case "$command" in
        setup)
            case "$platform" in
                macos)
                    setup_macos
                    ;;
                termux)
                    setup_termux
                    ;;
                ubuntu|wsl2)
                    if command -v systemctl &>/dev/null; then
                        setup_systemd
                    else
                        setup_cron
                    fi
                    ;;
                *)
                    log_error "Unsupported platform: $platform"
                    exit 1
                    ;;
            esac
            ;;
        remove)
            remove_scheduling "$platform"
            ;;
        status)
            show_status "$platform"
            ;;
        help|-h|--help)
            show_usage
            ;;
        *)
            log_error "Invalid command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
