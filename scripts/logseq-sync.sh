#!/usr/bin/env bash

# Logseq Cloud Sync Script
# Wrapper for sync:*:pcloud tasks - translates LOGSEQ_* variables to sync task variables

set -euo pipefail

# Calculate SCRIPT_DIR before changing directory
if [[ -z "${NOTIFY_SCRIPT:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    NOTIFY_SCRIPT="$SCRIPT_DIR/notify.sh"
fi

# Change to dotfiles directory to ensure Taskfile is found
cd "${DOTFILES_DIR:-$HOME/dotfiles}"

# Configuration
LOGSEQ_LOCAL="${LOGSEQ_LOCAL:-$HOME/logseq}"
LOGSEQ_REMOTE="${LOGSEQ_REMOTE:-app/logseq}"
LOG_FILE="${LOG_FILE:-$HOME/.local/share/logseq-sync.log}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.local/share/logseq-backups}"

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
    # Directories to check for conflict files
    local dirs=("$LOGSEQ_LOCAL/journals" "$LOGSEQ_LOCAL/pages")
    local all_conflicts=""

    # Collect conflict files from all directories
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local dir_conflicts=$(find "$dir" -name "*.conflict*" 2>/dev/null || true)
            if [[ -n "$dir_conflicts" ]]; then
                all_conflicts="${all_conflicts}${dir_conflicts}$(echo '')"
            fi
        fi
    done

    if [[ -z "$all_conflicts" ]]; then
        return
    fi

    # Find conflict files
    local conflicts="$all_conflicts"

    if [[ -z "$conflicts" ]]; then
        return
    fi

    log_warn "Found conflict files:"
    echo "$conflicts"
    echo ""

    # Send notification about conflicts
    if [[ -n "$NOTIFY_SCRIPT" ]] && [[ -x "$NOTIFY_SCRIPT" ]]; then
        local conflict_count=$(echo "$conflicts" | grep -c . || echo "0")
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

# Create backup before sync
create_backup() {
    local backup_date=$(date '+%Y%m%d_%H%M%S')
    local backup_path="$BACKUP_DIR/$backup_date"

    mkdir -p "$backup_path"
    log_info "Creating backup: $backup_path"

    # Backup directories that may have conflicts
    local dirs_to_backup=("journals" "pages")
    for dir in "${dirs_to_backup[@]}"; do
        if [[ -d "$LOGSEQ_LOCAL/$dir" ]]; then
            cp -r "$LOGSEQ_LOCAL/$dir" "$backup_path/" 2>/dev/null || true
        fi
    done

    # Keep only last 5 backups
    (cd "$BACKUP_DIR" && ls -t | tail -n +6 | xargs rm -rf 2>/dev/null) || true
}

# Check prerequisites
check_prerequisites() {
    if ! command -v task &>/dev/null; then
        log_error "task command not found. Please install Task: https://taskfile.dev"
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

# Main sync function
sync_logseq() {
    local direction="${1:-bidirectional}"
    shift || true

    # Map LOGSEQ_* variables to sync task variables
    local SOURCE_DIR="$LOGSEQ_LOCAL"
    local ENCRYPT_SUBDIR="${LOGSEQ_REMOTE}"
    local PARENT_DIR=""  # pcloud root directory

    echo "$(timestamp) - Starting sync ($direction) for $LOGSEQ_LOCAL -> $ENCRYPT_SUBDIR" >> "$LOG_FILE"
    log_info "Starting sync ($direction): $LOGSEQ_LOCAL -> $ENCRYPT_SUBDIR"

    # Common exclude patterns for Logseq
    local exclude=".git/**,node_modules/**,\.DS_Store,logseq/.recycle/**"

    case "$direction" in
        up|upload)
            log_info "Syncing local -> cloud (upload)..."
            set +e
            task sync:up:pcloud \
                SOURCE_DIR="$SOURCE_DIR" \
                ENCRYPT_SUBDIR="$ENCRYPT_SUBDIR" \
                PARENT_DIR="$PARENT_DIR" \
                EXCLUDE="$exclude" \
                -- "$@"
            local sync_result=$?
            set -e
            ;;
        down|download)
            log_info "Syncing cloud -> local (download)..."
            set +e
            task sync:down:pcloud \
                DIST_DIR="$SOURCE_DIR" \
                ENCRYPT_SUBDIR="$ENCRYPT_SUBDIR" \
                PARENT_DIR="$PARENT_DIR" \
                EXCLUDE="$exclude" \
                -- "$@"
            local sync_result=$?
            set -e
            ;;
        bidirectional|bi)
            # Create backup before bidirectional sync
            create_backup

            log_info "Syncing bidirectional (cloud <-> local)..."
            
            # Check for first-time bisync (need --resync flag if no tracking files exist)
            local remote_path=":crypt:${ENCRYPT_SUBDIR}"
            local needs_resync=false
            if ! rclone ls "${remote_path}.lst" &>/dev/null; then
                log_warn "First-time bisync detected. Adding --resync flag."
                needs_resync=true
            fi
            
            set +e
            if $needs_resync; then
                task sync:bisync:pcloud \
                    SOURCE_DIR="$SOURCE_DIR" \
                    ENCRYPT_SUBDIR="$ENCRYPT_SUBDIR" \
                    PARENT_DIR="$PARENT_DIR" \
                    EXCLUDE="$exclude" \
                    -- --resync "$@"
            else
                task sync:bisync:pcloud \
                    SOURCE_DIR="$SOURCE_DIR" \
                    ENCRYPT_SUBDIR="$ENCRYPT_SUBDIR" \
                    PARENT_DIR="$PARENT_DIR" \
                    EXCLUDE="$exclude" \
                    -- "$@"
            fi
            local sync_result=$?
            set -e

            # Check for and handle conflicts after bisync
            restore_conflicts
            ;;
        *)
            log_error "Invalid direction: $direction. Use: up, down, or bidirectional"
            return 1
            ;;
    esac

    # Check result and notify on failure
    if [[ $sync_result -ne 0 ]]; then
        log_error "Sync failed with exit code $sync_result"
        if [[ -n "$NOTIFY_SCRIPT" ]] && [[ -x "$NOTIFY_SCRIPT" ]]; then
            "$NOTIFY_SCRIPT" "Logseq Sync Failed" "Sync $direction failed with exit code $sync_result" "high" || true
        fi
        return $sync_result
    fi
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [direction]

Sync Logseq folder with pcloud encrypted storage using sync:*:pcloud tasks

Arguments:
  direction    Sync direction: up, down, or bidirectional (default: bidirectional)

Environment Variables:
  LOGSEQ_LOCAL    Local Logseq directory (default: ~/logseq)
  LOGSEQ_REMOTE   Remote path relative to pcloud root (default: app/logseq)
  LOG_FILE        Log file path (default: ~/.local/share/logseq-sync.log)
  BACKUP_DIR      Backup directory (default: ~/.local/share/logseq-backups)

Examples:
  $0              # Bidirectional sync
  $0 up           # Upload local -> cloud
  $0 down         # Download cloud -> local

First Sync:
  Run '$0 up' first to upload local files to cloud before bidirectional sync.

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
