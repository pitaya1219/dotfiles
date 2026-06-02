#!/usr/bin/env bash

set -euo pipefail

# Logseq Conflict Resolution Script
# Processes rclone conflict files and creates Logseq conflict pages

# Configuration
LOGSEQ_LOCAL="${LOGSEQ_LOCAL:-$HOME/logseq}"
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
        log_info "No conflict files found"
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
    if [[ ! -d "$LOGSEQ_LOCAL" ]]; then
        log_error "Logseq directory not found at $LOGSEQ_LOCAL"
        exit 1
    fi

    # Create directories
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$BACKUP_DIR"
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [options]

Process rclone conflict files and create Logseq conflict pages

Arguments:
  -h, --help    Show this help message

Environment Variables:
  LOGSEQ_LOCAL    Local Logseq directory (default: ~/logseq)
  LOG_FILE        Log file path (default: ~/.local/share/logseq-sync.log)
  BACKUP_DIR      Backup directory (default: ~/.local/share/logseq-backups)
  NOTIFY_SCRIPT   Path to notification script

Examples:
  $0              # Process all conflict files
  LOGSEQ_LOCAL=~/my-logseq $0

EOF
}

# Main
main() {
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        show_usage
        exit 0
    fi

    check_prerequisites
    restore_conflicts
}

main "$@"
