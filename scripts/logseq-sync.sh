#!/usr/bin/env bash

set -euo pipefail

# Logseq Cloud Sync Script
# Syncs Logseq folder with pcloud using rclone-secure

# Configuration
LOGSEQ_LOCAL="${LOGSEQ_LOCAL:-$HOME/logseq}"
LOGSEQ_REMOTE="${LOGSEQ_REMOTE:-pcloud-crypt:/logseq}"
RCLONE_BIN="${RCLONE_BIN:-$HOME/.local/bin/rclone-secure}"
LOG_FILE="${LOG_FILE:-$HOME/.local/share/logseq-sync.log}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.local/share/logseq-backups}"

# Scripts
if [[ -z "${NOTIFY_SCRIPT:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    NOTIFY_SCRIPT="$SCRIPT_DIR/notify.sh"
fi

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

# Check if Logseq is running
check_logseq_running() {
    if pgrep -f "Logseq" > /dev/null 2>&1; then
        log_warn "Logseq is currently running!"
        echo ""
        read -p "Continue sync anyway? This may cause conflicts. [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Sync cancelled. Please close Logseq and try again."
            exit 0
        fi
    fi
}

# Create backup before sync
create_backup() {
    local backup_date=$(date '+%Y%m%d_%H%M%S')
    local backup_path="$BACKUP_DIR/$backup_date"

    mkdir -p "$backup_path"

    log_info "Creating backup: $backup_path"

    # Backup journals directory (most likely to have conflicts)
    if [[ -d "$LOGSEQ_LOCAL/journals" ]]; then
        cp -r "$LOGSEQ_LOCAL/journals" "$backup_path/" 2>/dev/null || true
    fi

    # Keep only last 5 backups
    cd "$BACKUP_DIR"
    ls -t | tail -n +6 | xargs rm -rf 2>/dev/null || true
}

# Create conflict page in Logseq
create_conflict_page() {
    local base_file="$1"
    shift
    local conflict_files=("$@")

    # Get basename without extension (e.g., 2025_11_26)
    local basename=$(basename "$base_file" .md)
    local date_str=$(echo "$basename" | tr '_' '-')

    # Create pages directory if it doesn't exist
    mkdir -p "$LOGSEQ_LOCAL/pages"

    # Create conflict page
    local conflict_page="$LOGSEQ_LOCAL/pages/conflict-${date_str}.md"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Start building the conflict page
    {
        echo "tags:: #conflict"
        echo "created:: $timestamp"
        echo ""
        echo "# Conflict detected: [[${basename}]]"
        echo ""
        echo "Multiple versions of this journal page were found during sync."
        echo "Please review and manually merge the content below."
        echo ""

        # Add diff first if both versions exist
        if [[ -f "$base_file" ]] && [[ ${#conflict_files[@]} -gt 0 ]] && [[ -f "${conflict_files[0]}" ]]; then
            echo "## Diff Summary"
            echo ""
            echo "**Legend:** \`❌\` removed line (Conflict only) | \`✅\` added line (Current only) | \`  \` unchanged"
            echo ""
            echo '```'
            diff -u "${conflict_files[0]}" "$base_file" | tail -n +4 | sed 's/^-/❌ /' | sed 's/^+/✅ /' | sed 's/^@/📍/' || true
            echo ""
            echo '```'
            echo ""
        fi

        # Add each conflict version
        local version=1

        # First, show the original file if it exists (the "winner")
        if [[ -f "$base_file" ]]; then
            echo "## Version $version (Current/Newer)"
            echo "- collapsed:: true"
            # Indent each line to make it a child block
            sed 's/^/\t/' "$base_file"
            echo ""
            version=$((version + 1))
        fi

        # Then show conflict files (the "losers")
        for conflict_file in "${conflict_files[@]}"; do
            if [[ -f "$conflict_file" ]]; then
                echo "## Version $version (Conflict/Older)"
                echo "- collapsed:: true"
                # Indent each line to make it a child block
                sed 's/^/\t/' "$conflict_file"
                echo ""
                version=$((version + 1))
            fi
        done

        echo "---"
        echo "**Note:** After merging, update [[${basename}]] and delete this conflict page."
    } > "$conflict_page"

    log_info "Created conflict page: pages/conflict-${date_str}.md"
}

# Restore from conflict files
restore_conflicts() {
    local journals_dir="$LOGSEQ_LOCAL/journals"

    if [[ ! -d "$journals_dir" ]]; then
        return
    fi

    # Find conflict files
    local conflicts=$(find "$journals_dir" -name "*.conflict*" 2>/dev/null || true)

    if [[ -z "$conflicts" ]]; then
        return
    fi

    log_warn "Found conflict files:"
    echo "$conflicts"
    echo ""

    # Send notification about conflicts
    if [[ -n "$NOTIFY_SCRIPT" ]] && [[ -x "$NOTIFY_SCRIPT" ]]; then
        local conflict_count=$(echo "$conflicts" | wc -l | tr -d ' ')
        "$NOTIFY_SCRIPT" "Logseq Sync: Conflicts Detected" "Found $conflict_count conflict file(s). Check pages with #conflict tag in Logseq." "high" || true
    fi

    # Group conflicts by base file
    declare -A conflict_groups

    while IFS= read -r conflict_file; do
        if [[ -z "$conflict_file" ]]; then
            continue
        fi

        # Get base filename (remove .conflict-* suffix)
        local base_file="${conflict_file%%.conflict*}"
        # Add .md extension if not already present
        [[ "$base_file" != *.md ]] && base_file="${base_file}.md"

        # Add to group
        if [[ -z "${conflict_groups[$base_file]:-}" ]]; then
            conflict_groups[$base_file]="$conflict_file"
        else
            conflict_groups[$base_file]="${conflict_groups[$base_file]}|$conflict_file"
        fi
    done <<< "$conflicts"

    # Process each group of conflicts
    for base_file in "${!conflict_groups[@]}"; do
        log_warn "Processing conflicts for: $(basename "$base_file")"

        # Split conflict files by |
        IFS='|' read -ra conflict_array <<< "${conflict_groups[$base_file]}"

        # Check if there's actual difference before creating conflict page
        local has_diff=false
        if [[ -f "$base_file" ]] && [[ -f "${conflict_array[0]}" ]]; then
            if ! diff -q "$base_file" "${conflict_array[0]}" > /dev/null 2>&1; then
                has_diff=true
            fi
        elif [[ ! -f "$base_file" ]] || [[ ! -f "${conflict_array[0]}" ]]; then
            # One file missing means there's a real conflict
            has_diff=true
        fi

        if $has_diff; then
            # Create conflict page with all versions
            create_conflict_page "$base_file" "${conflict_array[@]}"

            # Clean up conflict files after creating conflict page
            log_info "Removing conflict files for: $(basename "$base_file")"
            for cf in "${conflict_array[@]}"; do
                [[ -f "$cf" ]] && rm -f "$cf"
            done
        else
            log_info "No actual difference found, skipping conflict page for: $(basename "$base_file")"
            # Clean up identical conflict files
            for cf in "${conflict_array[@]}"; do
                [[ -f "$cf" ]] && rm -f "$cf"
            done
        fi

        # If original file doesn't exist, use the largest conflict file
        if [[ ! -f "$base_file" ]]; then
            local largest=""
            local max_size=0

            for cf in "${conflict_array[@]}"; do
                if [[ -f "$cf" ]]; then
                    local size=$(stat -f%z "$cf" 2>/dev/null || stat -c%s "$cf" 2>/dev/null || echo "0")
                    if [[ $size -gt $max_size ]]; then
                        max_size=$size
                        largest="$cf"
                    fi
                fi
            done

            if [[ -n "$largest" ]]; then
                log_info "Restoring from largest conflict: $(basename "$largest")"
                cp "$largest" "$base_file"
            fi
        fi
    done
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

    # Create directories
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$BACKUP_DIR"
}

# Sync function
sync_logseq() {
    local direction="${1:-bidirectional}"
    shift || true

    echo "$(timestamp) - Starting sync ($direction)" >> "$LOG_FILE"

    # Check for running Logseq
    # check_logseq_running

    # Create backup before bidirectional sync
    if [[ "$direction" == "bidirectional" ]] || [[ "$direction" == "bi" ]]; then
        create_backup
    fi

    # Check if --dry-run is present
    local has_dryrun=false
    for arg in "$@"; do
        [[ "$arg" == "--dry-run" ]] && has_dryrun=true && break
    done

    local sync_status=0

    case "$direction" in
        up|upload)
            log_info "Syncing local → cloud..."
            set +e
            if $has_dryrun; then
                "$RCLONE_BIN" sync "$LOGSEQ_LOCAL" "$LOGSEQ_REMOTE" \
                    --exclude '.git/**' \
                    --exclude 'node_modules/**' \
                    --exclude '.DS_Store' \
                    --exclude 'logseq/.recycle/**' \
                    --progress \
                    "$@" 2>&1 | tee -a "$LOG_FILE"
                sync_status=${PIPESTATUS[0]}
            else
                "$RCLONE_BIN" sync "$LOGSEQ_LOCAL" "$LOGSEQ_REMOTE" \
                    --exclude '.git/**' \
                    --exclude 'node_modules/**' \
                    --exclude '.DS_Store' \
                    --exclude 'logseq/.recycle/**' \
                    --progress \
                    --log-file="$LOG_FILE" \
                    --log-level INFO \
                    "$@"
                sync_status=$?
            fi
            set -e
            ;;
        down|download)
            log_info "Syncing cloud → local..."
            set +e
            if $has_dryrun; then
                "$RCLONE_BIN" sync "$LOGSEQ_REMOTE" "$LOGSEQ_LOCAL" \
                    --exclude '.git/**' \
                    --exclude 'node_modules/**' \
                    --exclude '.DS_Store' \
                    --exclude 'logseq/.recycle/**' \
                    --progress \
                    "$@" 2>&1 | tee -a "$LOG_FILE"
                sync_status=${PIPESTATUS[0]}
            else
                "$RCLONE_BIN" sync "$LOGSEQ_REMOTE" "$LOGSEQ_LOCAL" \
                    --exclude '.git/**' \
                    --exclude 'node_modules/**' \
                    --exclude '.DS_Store' \
                    --exclude 'logseq/.recycle/**' \
                    --progress \
                    --log-file="$LOG_FILE" \
                    --log-level INFO \
                    "$@"
                sync_status=$?
            fi
            set -e
            ;;
        bidirectional|bi)
            log_info "Syncing bidirectional (cloud ↔ local)..."

            # Check if --resync is in arguments
            local has_resync=false
            for arg in "$@"; do
                [[ "$arg" == "--resync" ]] && has_resync=true && break
            done

            if ! $has_resync; then
                # Check if bisync listings exist
                BISYNC_CACHE="$HOME/.cache/rclone/bisync"
                LOCAL_EXPANDED="${LOGSEQ_LOCAL/#\~/$HOME}"
                LOCAL_ABSOLUTE="$(cd "$LOCAL_EXPANDED" && pwd)"
                LISTING_PREFIX="$(echo "$LOCAL_ABSOLUTE" | sed 's|/|_|g' | sed 's|^_||')..$(echo "$LOGSEQ_REMOTE" | sed 's|:|_|g; s|/|_|g')"

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

                    if [[ -n "$NOTIFY_SCRIPT" ]] && [[ -x "$NOTIFY_SCRIPT" ]]; then
                        local notify_msg="Init required. Options:
1. task sync:logseq -- up
2. task sync:logseq -- down
3. --resync (check dry-run first!)
Log: ${LOG_FILE:-~/.local/share/logseq-sync.log}"
                        "$NOTIFY_SCRIPT" "Logseq Sync: Init Required" "$notify_msg" "high" || true
                    fi

                    exit 1
                fi
            fi

            set +e
            if $has_dryrun; then
                "$RCLONE_BIN" bisync "$LOGSEQ_LOCAL" "$LOGSEQ_REMOTE" \
                    --exclude '.git/**' \
                    --exclude 'node_modules/**' \
                    --exclude '.DS_Store' \
                    --exclude 'logseq/.recycle/**' \
                    --resilient \
                    --recover \
                    --create-empty-src-dirs \
                    --conflict-resolve newer \
                    --conflict-loser pathname \
                    --conflict-suffix "conflict-{DateOnly}-" \
                    "$@" 2>&1 | tee -a "$LOG_FILE"
                sync_status=${PIPESTATUS[0]}
            else
                "$RCLONE_BIN" bisync "$LOGSEQ_LOCAL" "$LOGSEQ_REMOTE" \
                    --exclude '.git/**' \
                    --exclude 'node_modules/**' \
                    --exclude '.DS_Store' \
                    --exclude 'logseq/.recycle/**' \
                    --resilient \
                    --recover \
                    --create-empty-src-dirs \
                    --conflict-resolve newer \
                    --conflict-loser pathname \
                    --conflict-suffix "conflict-{DateOnly}-" \
                    --log-file="$LOG_FILE" \
                    --log-level INFO \
                    "$@"
                sync_status=$?
            fi
            set -e

            # Check for and handle conflicts
            restore_conflicts
            ;;
        *)
            log_error "Invalid direction: $direction. Use: up, down, or bidirectional"
            exit 1
            ;;
    esac

    if [[ $sync_status -eq 0 ]]; then
        log_info "Sync completed successfully"
        echo "$(timestamp) - Sync completed" >> "$LOG_FILE"
    else
        log_error "Sync failed"
        echo "$(timestamp) - Sync failed" >> "$LOG_FILE"

        if [[ -n "$NOTIFY_SCRIPT" ]] && [[ -x "$NOTIFY_SCRIPT" ]]; then
            "$NOTIFY_SCRIPT" "Logseq Sync Failed" "Failed to sync with cloud. Check log: ${LOG_FILE:-~/.local/share/logseq-sync.log}" "high" || true
        fi

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
  BACKUP_DIR      Backup directory (default: ~/.local/share/logseq-backups)

Examples:
  $0              # Bidirectional sync
  $0 up           # Upload local → cloud
  $0 down         # Download cloud → local

Backups:
  Automatic backups are created before bidirectional syncs
  Location: $BACKUP_DIR
  Last 5 backups are kept

EOF
}

# Main
main() {
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        show_usage
        exit 0
    fi

    check_prerequisites

    if [[ $# -eq 0 ]]; then
        sync_logseq "bidirectional"
    else
        sync_logseq "$@"
    fi
}

main "$@"
