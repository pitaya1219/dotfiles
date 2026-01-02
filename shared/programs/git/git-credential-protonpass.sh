#!/usr/bin/env bash
# Git credential helper for Proton Pass
# Supports host-based credential selection for GitHub, Gitea, etc.

set -euo pipefail

PASS_CLI="${HOME}/.local/bin/pass-cli"

# Parse git credential protocol input
parse_credential_input() {
    local protocol=""
    local host=""
    local username=""
    local password=""

    while IFS='=' read -r key value; do
        case "$key" in
            protocol) protocol="$value" ;;
            host) host="$value" ;;
            username) username="$value" ;;
            password) password="$value" ;;
        esac
    done

    echo "$protocol|$host|$username|$password"
}

# Get item title based on host
get_item_title_for_host() {
    local host="$1"

    case "$host" in
        github.com)
            echo "GitHub"
            ;;
        git.pitaya.f5.si)
            echo "git.pitaya.f5.si"
            ;;
        *)
            echo "Git"
            ;;
    esac
}

# Get credential from Proton Pass
get_credential() {
    local host="$1"
    local item_title
    item_title=$(get_item_title_for_host "$host")

    # Try to get the item from Proton Pass
    local output
    if ! output=$("$PASS_CLI" item view --vault-name Personal --item-title "$item_title" --output json 2>&1 | grep -v "ERROR MEMORY"); then
        # Item not found
        return 1
    fi

    # Parse JSON output to extract username and password
    local username password

    username=$(echo "$output" | jq -r '.item.content.content.Login.username // .item.content.content.Login.email // ""' 2>/dev/null || echo "")
    password=$(echo "$output" | jq -r '.item.content.content.Login.password // ""' 2>/dev/null || echo "")
    pat=$(echo "$output" | jq -r '.item.content.extra_fields[] | select(.name == "PAT").content.Hidden' 2>/dev/null || echo "")

    if [ -z "$password" ] && [ -z "$pat" ] ; then
        return 1
    fi

    echo "$username|$password|$pat"
}

# Git credential helper action: get
action_get() {
    local input
    input=$(cat)

    IFS='|' read -r protocol host username password <<< "$(echo "$input" | parse_credential_input)"

    if [ -z "$host" ]; then
        exit 1
    fi

    local cred
    if ! cred=$(get_credential "$host"); then
        exit 1
    fi

    IFS='|' read -r pass_username pass_password pass_pat <<< "$cred"

    # Output credential in git credential protocol format
    if [ -n "$pass_username" ]; then
        echo "username=$pass_username"
    fi
    # Prefer PAT over password for Git authentication
    if [ -n "$pass_pat" ]; then
        echo "password=$pass_pat"
    elif [ -n "$pass_password" ]; then
        echo "password=$pass_password"
    fi
}

# Git credential helper action: store
action_store() {
    # We don't store credentials back to Proton Pass
    # Just silently succeed
    cat > /dev/null
}

# Git credential helper action: erase
action_erase() {
    # We don't erase credentials from Proton Pass
    # Just silently succeed
    cat > /dev/null
}

# Main
case "${1:-}" in
    get)
        action_get
        ;;
    store)
        action_store
        ;;
    erase)
        action_erase
        ;;
    *)
        echo "Usage: $0 <get|store|erase>" >&2
        exit 1
        ;;
esac
