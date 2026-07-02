#!/usr/bin/env bash
# Claude Code PreToolUse hook to enforce session directory boundaries.
# Blocks Write/Edit operations outside the session directory.
# Fail-open: if session dir cannot be determined, allow the operation.

set -uo pipefail

# Read the hook input JSON from stdin
HOOK_INPUT=$(cat)

# Parse JSON using jq
TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // ""')
FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // ""')
BASH_COMMAND=$(echo "$HOOK_INPUT" | jq -r '.tool_input.command // ""')

# Allowlist patterns - paths that must never be blocked
# These are legitimate outside-session-dir targets
ALLOWLIST_PATTERNS=(
    "/home/*/dotfiles/"
    "/home/*/.dotfiles/"
    "/home/*/.claude/"
    "/home/*/.config/"
    "/home/*/.agent/"
    "/tmp/"
    "/home/lepetitprince/agent-sessions/"
)

# Function to check if a path matches any allowlist pattern
path_in_allowlist() {
    local path="$1"
    
    # Expand home directory for relative paths starting with ~
    if [[ "$path" == ~* ]]; then
        path="$(echo "$path" | sed "s|~|${HOME}|")"
    fi
    
    # Check against all allowlist patterns
    for pattern in "${ALLOWLIST_PATTERNS[@]}"; do
        if [[ "$path" == $pattern* ]]; then
            return 0
        fi
    done
    
    return 1
}

# Function to find the current session directory
find_session_dir() {
    # First, check CLAUDE_SESSION_DIR environment variable
    if [[ -n "${CLAUDE_SESSION_DIR:-}" ]] && [[ -d "$CLAUDE_SESSION_DIR" ]]; then
        echo "$CLAUDE_SESSION_DIR"
        return 0
    fi
    
    # Fallback: find the most recently modified session directory
    local session_dirs=()
    local agent_sessions_base="${HOME}/agent-sessions"
    
    # Look for session directories in the agent-sessions folder
    if [[ -d "$agent_sessions_base" ]]; then
        # Find all session directories (both direct and in subdirectories)
        while IFS= read -r -d '' dir; do
            session_dirs+=("$dir")
        done < <(find "$agent_sessions_base" -type d -name "session-*" -print0 2>/dev/null)
        
        # Sort by modification time (newest first) and pick the first
        if [[ ${#session_dirs[@]} -gt 0 ]]; then
            local newest_dir=""
            local newest_time=0
            
            for dir in "${session_dirs[@]}"; do
                if [[ -d "$dir" ]]; then
                    local mtime
                    mtime=$(stat -c %Y "$dir" 2>/dev/null || echo "0")
                    if [[ $mtime -gt $newest_time ]]; then
                        newest_time=$mtime
                        newest_dir="$dir"
                    fi
                fi
            done
            
            if [[ -n "$newest_dir" ]]; then
                echo "$newest_dir"
                return 0
            fi
        fi
    fi
    
    # Could not determine session directory
    echo ""
    return 1
}

# Function to normalize a path (expand tilde, make absolute, but don't follow symlinks)
normalize_path() {
    local path="$1"
    
    # Expand tilde
    if [[ "$path" == ~* ]]; then
        path="$(echo "$path" | sed "s|~|${HOME}|")"
    fi
    
    # If it's a relative path, resolve it relative to current directory
    if [[ "$path" != /* ]]; then
        path="$(pwd)/$path"
    fi
    
    # Remove trailing slashes for consistent comparison
    echo "$path" | sed 's|/$||'
}

# Main logic
main() {
    # If we can't parse the tool name, allow (fail-open)
    if [[ -z "$TOOL_NAME" ]]; then
        exit 0
    fi
    
    # Find the session directory
    SESSION_DIR=$(find_session_dir) || true
    
    # If no session directory found, allow (fail-open)
    if [[ -z "$SESSION_DIR" ]]; then
        exit 0
    fi
    
    # Normalize the session directory path
    SESSION_DIR=$(normalize_path "$SESSION_DIR")
    
    case "$TOOL_NAME" in
        "Write"|"Edit")
            # Handle file-based tools
            if [[ -n "$FILE_PATH" ]]; then
                NORMALIZED_PATH=$(normalize_path "$FILE_PATH")
                
                # Check if path is in allowlist
                if path_in_allowlist "$NORMALIZED_PATH"; then
                    exit 0
                fi
                
                # Check if path is within session directory
                # Add trailing slash to session dir for proper prefix matching
                SESSION_DIR_SLASH="${SESSION_DIR}/"
                
                if [[ "$NORMALIZED_PATH" == "$SESSION_DIR"* ]] || [[ "$NORMALIZED_PATH" == "$SESSION_DIR_SLASH"* ]]; then
                    # Path is within session directory
                    exit 0
                else
                    # Path is outside session directory and not in allowlist - BLOCK
                    echo "Session dir violation: '${FILE_PATH}' is outside your session directory." >&2
                    echo "Your session dir is '${SESSION_DIR}'. Create your working files there." >&2
                    echo "To work on a repo, clone it inside your session dir first." >&2
                    echo "Exception: ~/dotfiles, ~/.claude, ~/.config, ~/.agent, /tmp are always allowed." >&2
                    exit 2
                fi
            fi
            ;;
        "Bash")
            # For Bash commands, allow all for now
            # Conservative heuristic checking is complex and error-prone
            # The Write/Edit hooks provide the main protection
            exit 0
            ;;
        *)
            # For all other tools, allow
            exit 0
            ;;
    esac
    
    # Default: allow
    exit 0
}

# Run main function
main "$@"