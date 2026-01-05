#!/usr/bin/env bash

# proton-passage-sync.sh
# Bidirectional sync between Proton Pass and passage
# See: .ai/sessions/20260105-proton-passage-sync-plan.md

set -euo pipefail

# ============================================
# Constants
# ============================================

VAULT_NAME="Passage"
SCRIPT_NAME="$(basename "$0")"

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================
# Utility Functions
# ============================================

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

die() {
    log_error "$*"
    exit 1
}

separator() {
    echo ""
    echo "================================================="
}

# ============================================
# Prerequisite Checks
# ============================================

check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        return 1
    fi
    return 0
}

check_proton_auth() {
    if ! pass-cli test &> /dev/null; then
        return 1
    fi
    return 0
}

check_passage_access() {
    if ! passage list &> /dev/null; then
        return 1
    fi
    return 0
}

get_vault_id() {
    pass-cli vault list --format json 2>/dev/null | \
        jq -r ".[] | select(.name==\"$VAULT_NAME\") | .id" || echo ""
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local all_ok=true
    
    # Check commands
    if check_command pass-cli; then
        log_success "pass-cli found"
    else
        log_error "pass-cli not found. Install it via: task setup"
        all_ok=false
    fi
    
    if check_command passage; then
        log_success "passage found"
    else
        log_error "passage not found"
        all_ok=false
    fi
    
    if check_command jq; then
        log_success "jq found"
    else
        log_error "jq not found"
        all_ok=false
    fi
    
    if [ "$all_ok" = false ]; then
        die "Missing required tools"
    fi
    
    # Check authentication
    if check_proton_auth; then
        log_success "Proton Pass authenticated"
    else
        die "Not authenticated to Proton Pass. Run: pass-cli login"
    fi
    
    # Check passage access
    if check_passage_access; then
        log_success "passage store accessible"
    else
        die "Cannot access passage store. Ensure GPG key is unlocked."
    fi
    
    # Check vault
    local vault_id
    vault_id=$(get_vault_id)
    if [ -z "$vault_id" ]; then
        log_error "Vault '$VAULT_NAME' not found in Proton Pass"
        echo ""
        echo "Create it with one of these commands:"
        echo "  task secret:vault:create"
        echo "  task secret:init:proton"
        exit 1
    fi
    log_success "Vault '$VAULT_NAME' found (ID: ${vault_id:0:12}...)"
    
    echo ""
    log_success "All checks passed!"
    echo ""
}

# ============================================
# Data Access Functions
# ============================================

scan_passage() {
    local path_filter="$1"
    
    passage list 2>/dev/null | grep -v '^$' | while read -r entry; do
        # Skip if path filter is set and entry doesn't match
        if [ -n "$path_filter" ] && [[ ! "$entry" =~ ^"$path_filter" ]]; then
            continue
        fi
        echo "$entry"
    done
}

scan_proton() {
    local vault_id="$1"
    local path_filter="$2"
    
    pass-cli item list --vault "$vault_id" --format json 2>/dev/null | \
        jq -r '.[] | .id + "|" + .name + "|" + (.metadata.itemVersion // "")' | \
        while IFS='|' read -r item_id name version; do
            # Skip if path filter is set and name doesn't match
            if [ -n "$path_filter" ] && [[ ! "$name" =~ ^"$path_filter" ]]; then
                continue
            fi
            echo "$item_id|$name|$version"
        done
}

get_passage_value() {
    local path="$1"
    passage show "$path" 2>/dev/null || echo ""
}

get_proton_item() {
    local item_id="$1"
    pass-cli item view --item "$item_id" --format json 2>/dev/null || echo ""
}

get_proton_value() {
    local item_id="$1"
    local item_json
    item_json=$(get_proton_item "$item_id")
    echo "$item_json" | jq -r '.content.loginFields.password // ""'
}

get_proton_username() {
    local item_id="$1"
    local item_json
    item_json=$(get_proton_item "$item_id")
    echo "$item_json" | jq -r '.content.loginFields.username // ""'
}

get_proton_metadata() {
    local item_id="$1"
    local field="$2"
    local item_json
    item_json=$(get_proton_item "$item_id")
    echo "$item_json" | jq -r ".metadata.${field} // \"\""
}

# ============================================
# CRUD Operations
# ============================================

create_proton_item() {
    local vault_id="$1"
    local name="$2"
    local passage_path="$3"
    local value="$4"
    
    # Create login item with username=passage_path, password=value
    pass-cli item create \
        --vault "$vault_id" \
        --name "$name" \
        --username "$passage_path" \
        --password "$value" \
        &> /dev/null
}

update_proton_item() {
    local item_id="$1"
    local value="$2"
    
    pass-cli item update \
        --item "$item_id" \
        --password "$value" \
        &> /dev/null
}

create_passage_entry() {
    local path="$1"
    local value="$2"
    
    echo "$value" | passage insert -e "$path" &> /dev/null
}

update_passage_entry() {
    local path="$1"
    local value="$2"
    
    echo "$value" | passage insert -ef "$path" &> /dev/null
}

# ============================================
# Comparison Logic
# ============================================

compare_entries() {
    local vault_id="$1"
    local path_filter="$2"
    
    # Create associative arrays (bash 4+)
    declare -A passage_entries
    declare -A proton_entries
    declare -A proton_ids
    
    # Scan passage
    while read -r entry; do
        [ -z "$entry" ] && continue
        passage_entries["$entry"]=1
    done < <(scan_passage "$path_filter")
    
    # Scan Proton Pass
    while IFS='|' read -r item_id name version; do
        [ -z "$item_id" ] && continue
        proton_entries["$name"]=1
        proton_ids["$name"]="$item_id"
    done < <(scan_proton "$vault_id" "$path_filter")
    
    # Categorize entries
    local -a in_sync=()
    local -a modified=()
    local -a passage_only=()
    local -a proton_only=()
    
    # Check passage entries
    for path in "${!passage_entries[@]}"; do
        if [ -n "${proton_entries[$path]:-}" ]; then
            # Exists in both - check if values match
            local passage_val proton_val
            passage_val=$(get_passage_value "$path")
            proton_val=$(get_proton_value "${proton_ids[$path]}")
            
            if [ "$passage_val" = "$proton_val" ]; then
                in_sync+=("$path")
            else
                modified+=("$path|${proton_ids[$path]}")
            fi
        else
            # Only in passage
            passage_only+=("$path")
        fi
    done
    
    # Check Proton-only entries
    for name in "${!proton_entries[@]}"; do
        if [ -z "${passage_entries[$name]:-}" ]; then
            proton_only+=("$name|${proton_ids[$name]}")
        fi
    done
    
    # Output results as JSON-like format for parsing
    echo "IN_SYNC:${#in_sync[@]}"
    for item in "${in_sync[@]}"; do
        echo "IN_SYNC:$item"
    done
    
    echo "MODIFIED:${#modified[@]}"
    for item in "${modified[@]}"; do
        echo "MODIFIED:$item"
    done
    
    echo "PASSAGE_ONLY:${#passage_only[@]}"
    for item in "${passage_only[@]}"; do
        echo "PASSAGE_ONLY:$item"
    done
    
    echo "PROTON_ONLY:${#proton_only[@]}"
    for item in "${proton_only[@]}"; do
        echo "PROTON_ONLY:$item"
    done
}

# ============================================
# Interactive Sync
# ============================================

handle_modified() {
    local path="$1"
    local item_id="$2"
    local counter="$3"
    local total="$4"
    
    separator
    echo -e "${CYAN}[$counter/$total] $path${NC}"
    echo "  Status: ${YELLOW}MODIFIED${NC}"
    echo ""
    
    local passage_val proton_val
    passage_val=$(get_passage_value "$path")
    proton_val=$(get_proton_value "$item_id")
    
    local last_synced
    last_synced=$(get_proton_metadata "$item_id" "modifyTime")
    
    echo "  Proton Pass:"
    echo "    Value: ***"
    if [ -n "$last_synced" ]; then
        echo "    Last modified: $last_synced"
    fi
    echo ""
    echo "  passage:"
    echo "    Value: ***"
    echo ""
    
    while true; do
        echo "  Actions:"
        echo "    ${GREEN}[P]${NC} Use Proton Pass version (update passage)"
        echo "    ${GREEN}[L]${NC} Use passage version (update Proton Pass)"
        echo "    ${BLUE}[D]${NC} Show values"
        echo "    ${YELLOW}[S]${NC} Skip"
        echo "    ${RED}[Q]${NC} Quit"
        echo ""
        read -r -p "  Choice: " choice
        
        case "$choice" in
            P|p)
                update_passage_entry "$path" "$proton_val"
                log_success "Updated passage from Proton Pass"
                return 0
                ;;
            L|l)
                update_proton_item "$item_id" "$passage_val"
                log_success "Updated Proton Pass from passage"
                return 0
                ;;
            D|d)
                echo ""
                echo "  ${CYAN}--- Proton Pass ---${NC}"
                echo "  $proton_val"
                echo ""
                echo "  ${CYAN}--- passage ---${NC}"
                echo "  $passage_val"
                echo ""
                ;;
            S|s)
                log_info "Skipped"
                return 0
                ;;
            Q|q)
                log_info "Quit by user"
                exit 0
                ;;
            *)
                log_warning "Invalid choice. Try again."
                ;;
        esac
    done
}

handle_passage_only() {
    local path="$1"
    local vault_id="$2"
    local counter="$3"
    local total="$4"
    
    separator
    echo -e "${CYAN}[$counter/$total] $path${NC}"
    echo "  Status: ${YELLOW}ONLY IN PASSAGE${NC}"
    echo ""
    
    local passage_val
    passage_val=$(get_passage_value "$path")
    
    echo "  passage:"
    echo "    Value: ***"
    echo ""
    
    while true; do
        echo "  Actions:"
        echo "    ${GREEN}[C]${NC} Create in Proton Pass"
        echo "    ${BLUE}[D]${NC} Show value"
        echo "    ${YELLOW}[S]${NC} Skip"
        echo "    ${RED}[Q]${NC} Quit"
        echo ""
        read -r -p "  Choice: " choice
        
        case "$choice" in
            C|c)
                create_proton_item "$vault_id" "$path" "$path" "$passage_val"
                log_success "Created in Proton Pass"
                return 0
                ;;
            D|d)
                echo ""
                echo "  ${CYAN}--- passage ---${NC}"
                echo "  $passage_val"
                echo ""
                ;;
            S|s)
                log_info "Skipped"
                return 0
                ;;
            Q|q)
                log_info "Quit by user"
                exit 0
                ;;
            *)
                log_warning "Invalid choice. Try again."
                ;;
        esac
    done
}

handle_proton_only() {
    local name="$1"
    local item_id="$2"
    local counter="$3"
    local total="$4"
    
    separator
    echo -e "${CYAN}[$counter/$total] $name${NC}"
    echo "  Status: ${YELLOW}ONLY IN PROTON PASS${NC}"
    echo ""
    
    local proton_val passage_path
    proton_val=$(get_proton_value "$item_id")
    passage_path=$(get_proton_username "$item_id")
    
    # Use username field as passage path, fallback to item name
    if [ -z "$passage_path" ] || [ "$passage_path" = "null" ]; then
        passage_path="$name"
    fi
    
    echo "  Proton Pass:"
    echo "    Value: ***"
    echo "    Passage path: $passage_path"
    echo ""
    
    while true; do
        echo "  Actions:"
        echo "    ${GREEN}[C]${NC} Create in passage"
        echo "    ${BLUE}[D]${NC} Show value"
        echo "    ${YELLOW}[S]${NC} Skip"
        echo "    ${RED}[Q]${NC} Quit"
        echo ""
        read -r -p "  Choice: " choice
        
        case "$choice" in
            C|c)
                create_passage_entry "$passage_path" "$proton_val"
                log_success "Created in passage"
                return 0
                ;;
            D|d)
                echo ""
                echo "  ${CYAN}--- Proton Pass ---${NC}"
                echo "  $proton_val"
                echo ""
                ;;
            S|s)
                log_info "Skipped"
                return 0
                ;;
            Q|q)
                log_info "Quit by user"
                exit 0
                ;;
            *)
                log_warning "Invalid choice. Try again."
                ;;
        esac
    done
}

interactive_sync() {
    local vault_id="$1"
    local path_filter="$2"
    local sync_mode="$3" # "bidirectional", "proton-to-passage", "passage-to-proton"
    
    log_info "Scanning passage store..."
    local passage_count
    passage_count=$(scan_passage "$path_filter" | wc -l)
    echo "Found $passage_count passage entries"
    echo ""
    
    log_info "Scanning Proton Pass (Vault: $VAULT_NAME)..."
    local proton_count
    proton_count=$(scan_proton "$vault_id" "$path_filter" | wc -l)
    echo "Found $proton_count Proton Pass items"
    echo ""
    
    log_info "Comparing entries..."
    
    # Parse comparison results
    local -a in_sync=()
    local -a modified=()
    local -a passage_only=()
    local -a proton_only=()
    
    while IFS=':' read -r category data; do
        case "$category" in
            IN_SYNC)
                if [[ "$data" =~ ^[0-9]+$ ]]; then
                    continue
                fi
                in_sync+=("$data")
                ;;
            MODIFIED)
                if [[ "$data" =~ ^[0-9]+$ ]]; then
                    continue
                fi
                modified+=("$data")
                ;;
            PASSAGE_ONLY)
                if [[ "$data" =~ ^[0-9]+$ ]]; then
                    continue
                fi
                passage_only+=("$data")
                ;;
            PROTON_ONLY)
                if [[ "$data" =~ ^[0-9]+$ ]]; then
                    continue
                fi
                proton_only+=("$data")
                ;;
        esac
    done < <(compare_entries "$vault_id" "$path_filter")
    
    # Calculate totals
    local total_entries=$((${#in_sync[@]} + ${#modified[@]} + ${#passage_only[@]} + ${#proton_only[@]}))
    local needs_action=$((${#modified[@]} + ${#passage_only[@]} + ${#proton_only[@]}))
    
    separator
    echo "Sync Status"
    separator
    echo "  Total entries: $total_entries"
    echo "  ${GREEN}In sync: ${#in_sync[@]}${NC}"
    echo "  ${YELLOW}Modified: ${#modified[@]}${NC}"
    echo "  ${YELLOW}Only in passage: ${#passage_only[@]}${NC}"
    echo "  ${YELLOW}Only in Proton Pass: ${#proton_only[@]}${NC}"
    separator
    
    if [ "$needs_action" -eq 0 ]; then
        log_success "Everything is in sync!"
        return 0
    fi
    
    echo ""
    log_info "Processing $needs_action entries..."
    echo ""
    
    local counter=0
    
    # Handle modified entries
    if [ "$sync_mode" = "bidirectional" ] || [ "$sync_mode" = "proton-to-passage" ] || [ "$sync_mode" = "passage-to-proton" ]; then
        for item in "${modified[@]}"; do
            counter=$((counter + 1))
            IFS='|' read -r path item_id <<< "$item"
            handle_modified "$path" "$item_id" "$counter" "$needs_action"
        done
    fi
    
    # Handle passage-only entries
    if [ "$sync_mode" = "bidirectional" ] || [ "$sync_mode" = "passage-to-proton" ]; then
        for path in "${passage_only[@]}"; do
            counter=$((counter + 1))
            handle_passage_only "$path" "$vault_id" "$counter" "$needs_action"
        done
    fi
    
    # Handle Proton-only entries
    if [ "$sync_mode" = "bidirectional" ] || [ "$sync_mode" = "proton-to-passage" ]; then
        for item in "${proton_only[@]}"; do
            counter=$((counter + 1))
            IFS='|' read -r name item_id <<< "$item"
            handle_proton_only "$name" "$item_id" "$counter" "$needs_action"
        done
    fi
    
    separator
    log_success "Sync completed!"
    separator
}

# ============================================
# Status Display
# ============================================

status_only() {
    local vault_id="$1"
    local path_filter="$2"
    
    log_info "Scanning passage store..."
    local passage_count
    passage_count=$(scan_passage "$path_filter" | wc -l)
    echo "Found $passage_count passage entries"
    echo ""
    
    log_info "Scanning Proton Pass (Vault: $VAULT_NAME)..."
    local proton_count
    proton_count=$(scan_proton "$vault_id" "$path_filter" | wc -l)
    echo "Found $proton_count Proton Pass items"
    echo ""
    
    log_info "Comparing entries..."
    
    # Parse comparison results
    local -a in_sync=()
    local -a modified=()
    local -a passage_only=()
    local -a proton_only=()
    
    while IFS=':' read -r category data; do
        case "$category" in
            IN_SYNC)
                if [[ "$data" =~ ^[0-9]+$ ]]; then
                    continue
                fi
                in_sync+=("$data")
                ;;
            MODIFIED)
                if [[ "$data" =~ ^[0-9]+$ ]]; then
                    continue
                fi
                modified+=("$data")
                ;;
            PASSAGE_ONLY)
                if [[ "$data" =~ ^[0-9]+$ ]]; then
                    continue
                fi
                passage_only+=("$data")
                ;;
            PROTON_ONLY)
                if [[ "$data" =~ ^[0-9]+$ ]]; then
                    continue
                fi
                proton_only+=("$data")
                ;;
        esac
    done < <(compare_entries "$vault_id" "$path_filter")
    
    separator
    echo "Sync Status (No changes will be made)"
    separator
    echo "  Total entries: $((${#in_sync[@]} + ${#modified[@]} + ${#passage_only[@]} + ${#proton_only[@]}))"
    echo "  ${GREEN}In sync: ${#in_sync[@]}${NC}"
    echo "  ${YELLOW}Modified: ${#modified[@]}${NC}"
    echo "  ${YELLOW}Only in passage: ${#passage_only[@]}${NC}"
    echo "  ${YELLOW}Only in Proton Pass: ${#proton_only[@]}${NC}"
    separator
    echo ""
    echo "Detailed status:"
    echo ""
    
    for path in "${in_sync[@]}"; do
        echo "  ${GREEN}✓${NC} $path"
    done
    
    for item in "${modified[@]}"; do
        IFS='|' read -r path _ <<< "$item"
        echo "  ${YELLOW}⚠${NC} $path (modified in both)"
    done
    
    for path in "${passage_only[@]}"; do
        echo "  ${YELLOW}⚠${NC} $path (only in passage)"
    done
    
    for item in "${proton_only[@]}"; do
        IFS='|' read -r name _ <<< "$item"
        echo "  ${YELLOW}⚠${NC} $name (only in Proton Pass)"
    done
    
    echo ""
    
    if [ "${#modified[@]}" -gt 0 ] || [ "${#passage_only[@]}" -gt 0 ] || [ "${#proton_only[@]}" -gt 0 ]; then
        log_info "Run 'task secret:sync' to synchronize entries."
    else
        log_success "Everything is in sync!"
    fi
}

# ============================================
# Initialization Functions
# ============================================

init_proton() {
    check_prerequisites
    
    local vault_id
    vault_id=$(get_vault_id)
    
    log_info "Initializing Proton Pass from passage..."
    echo ""
    
    # Count entries
    local entries
    entries=$(scan_passage "")
    local total
    total=$(echo "$entries" | wc -l)
    
    echo "Found $total entries in passage"
    echo ""
    
    log_info "Importing to Proton Pass..."
    
    local created=0
    local skipped=0
    local failed=0
    local counter=0
    
    while read -r path; do
        [ -z "$path" ] && continue
        counter=$((counter + 1))
        
        local value
        value=$(get_passage_value "$path")
        
        if create_proton_item "$vault_id" "$path" "$path" "$value"; then
            echo "  [$counter/$total] $path ... ${GREEN}created${NC}"
            created=$((created + 1))
        else
            echo "  [$counter/$total] $path ... ${RED}failed${NC}"
            failed=$((failed + 1))
        fi
    done <<< "$entries"
    
    separator
    echo "Import Summary"
    separator
    echo "  Total entries: $total"
    echo "  ${GREEN}Created: $created${NC}"
    echo "  ${YELLOW}Skipped (already exist): $skipped${NC}"
    echo "  ${RED}Failed: $failed${NC}"
    separator
}

init_passage() {
    check_prerequisites
    
    local vault_id
    vault_id=$(get_vault_id)
    
    log_info "Initializing passage from Proton Pass..."
    echo ""
    
    log_warning "This will overwrite existing passage entries with the same path!"
    read -r -p "Continue? [y/N] " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Cancelled by user"
        return 0
    fi
    
    echo ""
    
    # Count entries
    local entries
    entries=$(scan_proton "$vault_id" "")
    local total
    total=$(echo "$entries" | wc -l)
    
    echo "Found $total items in Proton Pass"
    echo ""
    
    log_info "Importing to passage..."
    
    local created=0
    local failed=0
    local counter=0
    
    while IFS='|' read -r item_id name _; do
        [ -z "$item_id" ] && continue
        counter=$((counter + 1))
        
        local value passage_path
        value=$(get_proton_value "$item_id")
        passage_path=$(get_proton_username "$item_id")
        
        # Use username field as passage path, fallback to item name
        if [ -z "$passage_path" ] || [ "$passage_path" = "null" ]; then
            passage_path="$name"
        fi
        
        if create_passage_entry "$passage_path" "$value"; then
            echo "  [$counter/$total] $passage_path ... ${GREEN}created${NC}"
            created=$((created + 1))
        else
            echo "  [$counter/$total] $passage_path ... ${RED}failed${NC}"
            failed=$((failed + 1))
        fi
    done <<< "$entries"
    
    separator
    echo "Import Summary"
    separator
    echo "  Total items: $total"
    echo "  ${GREEN}Created: $created${NC}"
    echo "  ${RED}Failed: $failed${NC}"
    separator
}

# ============================================
# Main Command Router
# ============================================

usage() {
    cat << EOF
Usage: $SCRIPT_NAME <command> [path]

Commands:
  check                   Check prerequisites and authentication
  sync [PATH]            Bidirectional sync (interactive)
  status [PATH]          Show sync status without changes
  proton-to-passage [PATH]  One-way sync: Proton Pass → passage
  passage-to-proton [PATH]  One-way sync: passage → Proton Pass
  init-proton            Initialize Proton Pass from passage
  init-passage           Initialize passage from Proton Pass

Optional Arguments:
  PATH                   Filter entries by path prefix (e.g., homelab/gitea)

Examples:
  $SCRIPT_NAME check
  $SCRIPT_NAME sync
  $SCRIPT_NAME sync homelab/gitea
  $SCRIPT_NAME status
  $SCRIPT_NAME init-proton

EOF
}

main() {
    local command="${1:-}"
    local path_filter="${2:-}"
    
    if [ -z "$command" ]; then
        usage
        exit 1
    fi
    
    case "$command" in
        check)
            check_prerequisites
            ;;
        sync)
            check_prerequisites
            local vault_id
            vault_id=$(get_vault_id)
            interactive_sync "$vault_id" "$path_filter" "bidirectional"
            ;;
        status)
            check_prerequisites
            local vault_id
            vault_id=$(get_vault_id)
            status_only "$vault_id" "$path_filter"
            ;;
        proton-to-passage)
            check_prerequisites
            local vault_id
            vault_id=$(get_vault_id)
            interactive_sync "$vault_id" "$path_filter" "proton-to-passage"
            ;;
        passage-to-proton)
            check_prerequisites
            local vault_id
            vault_id=$(get_vault_id)
            interactive_sync "$vault_id" "$path_filter" "passage-to-proton"
            ;;
        init-proton)
            init_proton
            ;;
        init-passage)
            init_passage
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            usage
            exit 1
            ;;
    esac
}

main "$@"
