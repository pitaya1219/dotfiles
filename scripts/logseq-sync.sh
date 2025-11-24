#!/usr/bin/env bash

set -euo pipefail

# Logseq Cloud Sync Script
# Syncs Logseq folder with pcloud using rclone-secure

# Configuration
LOGSEQ_LOCAL="${LOGSEQ_LOCAL:-$HOME/logseq}"
LOGSEQ_REMOTE="${LOGSEQ_REMOTE:-pcloud-crypt:/logseq}"
RCLONE_BIN="${RCLONE_BIN:-$HOME/.local/bin/rclone-secure}"
LOG_FILE="${LOG_FILE:-$HOME/.local/share/logseq-sync.log}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Helper functions
log_info() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"
}

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Validate prerequisites
check_prerequisites() {
    if [[ ! -x "$RCLONE_BIN" ]]; then
        log_error "rclone-secure not found at $RCLONE_BIN"
        exit 1
    fi

    if [[ ! -d "$LOGSEQ_LOCAL" ]]; then
        log_error "Logseq directory not found at $LOGSEQ_LOCAL"
        exit 1
    fi

    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
}

# Sync function
sync_logseq() {
    local direction="${1:-bidirectional}"

    echo "$(timestamp) - Starting sync ($direction)" >> "$LOG_FILE"

    case "$direction" in
        up|upload)
            log_info "Syncing local → cloud..."
            "$RCLONE_BIN" sync "$LOGSEQ_LOCAL" "$LOGSEQ_REMOTE" \
                --exclude '.git/**' \
                --exclude 'node_modules/**' \
                --exclude '.DS_Store' \
                --exclude 'logseq/.recycle/**' \
                --progress \
                --log-file="$LOG_FILE" \
                --log-level INFO
            ;;
        down|download)
            log_info "Syncing cloud → local..."
            "$RCLONE_BIN" sync "$LOGSEQ_REMOTE" "$LOGSEQ_LOCAL" \
                --exclude '.git/**' \
                --exclude 'node_modules/**' \
                --exclude '.DS_Store' \
                --exclude 'logseq/.recycle/**' \
                --progress \
                --log-file="$LOG_FILE" \
                --log-level INFO
            ;;
        bidirectional|bi)
            log_info "Syncing bidirectional (cloud ↔ local)..."

            # Check if bisync listings exist, if not, notify user
            BISYNC_CACHE="$HOME/.cache/rclone/bisync"
            # Expand tilde and resolve to absolute path for listing filename
            LOCAL_EXPANDED="${LOGSEQ_LOCAL/#\~/$HOME}"
            LOCAL_ABSOLUTE="$(cd "$LOCAL_EXPANDED" && pwd)"
            LISTING_PREFIX="$(echo "$LOCAL_ABSOLUTE" | sed 's|/|_|g')..$(echo "$LOGSEQ_REMOTE" | sed 's|:|_|g; s|/|_|g')"

            if [[ ! -f "$BISYNC_CACHE/${LISTING_PREFIX}.path1.lst" ]] || [[ ! -f "$BISYNC_CACHE/${LISTING_PREFIX}.path2.lst" ]]; then
                log_error "First sync detected. Bisync requires initialization with --resync flag."
                echo ""
                echo "Run one of the following commands to initialize:"
                echo "  1. Upload local to cloud:  $0 up"
                echo "  2. Download cloud to local: $0 down"
                echo "  3. Force resync (WARNING: may overwrite conflicts):"
                echo ""
                echo "     Preview changes first (dry-run):"
                echo "     $RCLONE_BIN bisync \"$LOGSEQ_LOCAL\" \"$LOGSEQ_REMOTE\" --resync --dry-run"
                echo ""
                echo "     Apply the sync:"
                echo "     $RCLONE_BIN bisync \"$LOGSEQ_LOCAL\" \"$LOGSEQ_REMOTE\" --resync"
                echo ""
                exit 1
            fi

            "$RCLONE_BIN" bisync "$LOGSEQ_LOCAL" "$LOGSEQ_REMOTE" \
                --exclude '.git/**' \
                --exclude 'node_modules/**' \
                --exclude '.DS_Store' \
                --exclude 'logseq/.recycle/**' \
                --resilient \
                --recover \
                --create-empty-src-dirs \
                --log-file="$LOG_FILE" \
                --log-level INFO
            ;;
        *)
            log_error "Invalid direction: $direction. Use: up, down, or bidirectional"
            exit 1
            ;;
    esac

    if [[ $? -eq 0 ]]; then
        log_info "Sync completed successfully"
        echo "$(timestamp) - Sync completed" >> "$LOG_FILE"
    else
        log_error "Sync failed"
        echo "$(timestamp) - Sync failed" >> "$LOG_FILE"
        exit 1
    fi
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [direction]

Sync Logseq folder with cloud storage using rclone-secure

Arguments:
  direction    Sync direction: up, down, or bidirectional (default: bidirectional)

Environment Variables:
  LOGSEQ_LOCAL    Local Logseq directory (default: ~/logseq)
  LOGSEQ_REMOTE   Remote path (default: pcloud-crypt:/logseq)
  RCLONE_BIN      Path to rclone-secure (default: ~/.local/bin/rclone-secure)
  LOG_FILE        Log file path (default: ~/.local/share/logseq-sync.log)

Examples:
  $0              # Bidirectional sync
  $0 up           # Upload local → cloud
  $0 down         # Download cloud → local

EOF
}

# Main
main() {
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        show_usage
        exit 0
    fi

    check_prerequisites
    sync_logseq "${1:-bidirectional}"
}

main "$@"
