# LLM Bash Completion (llama.cpp backend with ZITADEL auth)
# Trigger: Ctrl+G

LLM_COMPLETE_URL="${LLM_COMPLETE_URL:-https://ai.pitaya.f5.si}"
LLM_COMPLETE_MODEL="${LLM_COMPLETE_MODEL:-qwen2.5-coder-1.5b-Q4_K_M}"
LLM_COMPLETE_TIMEOUT="${LLM_COMPLETE_TIMEOUT:-5}"
LLM_DEBUG="${LLM_DEBUG:-0}"
LLM_DEBUG_LOG="${LLM_DEBUG_LOG:-/tmp/llm-complete-debug.log}"

_llm_debug() {
    [[ "$LLM_DEBUG" == "1" ]] && echo "[$(date '+%H:%M:%S')] $*" >> "$LLM_DEBUG_LOG"
}
LLM_TOKEN_URL="${LLM_TOKEN_URL:-https://auth.pitaya.f5.si/oauth/v2/token}"
LLM_CLIENT_ID_PATH="${LLM_CLIENT_ID_PATH:-bash/llama-cpp/client/id}"
LLM_CLIENT_SECRET_PATH="${LLM_CLIENT_SECRET_PATH:-bash/llama-cpp/client/secret}"
LLM_TOKEN_CACHE="${LLM_TOKEN_CACHE:-$HOME/.cache/llm-complete-token}"

_llm_get_token() {
    local cache_file="$LLM_TOKEN_CACHE"
    local now=$(date +%s)

    # Check cached token
    if [[ -f "$cache_file" ]]; then
        local cached=$(cat "$cache_file" 2>/dev/null)
        local token=$(echo "$cached" | cut -d'|' -f1)
        local expires=$(echo "$cached" | cut -d'|' -f2)
        if [[ -n "$token" && -n "$expires" && "$now" -lt "$expires" ]]; then
            echo "$token"
            return 0
        fi
    fi

    # Get new token
    local client_id=$(passage show "$LLM_CLIENT_ID_PATH" 2>/dev/null)
    local client_secret=$(passage show "$LLM_CLIENT_SECRET_PATH" 2>/dev/null)

    if [[ -z "$client_id" || -z "$client_secret" ]]; then
        return 1
    fi

    local response=$(curl -s --max-time 5 -X POST "$LLM_TOKEN_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=client_credentials" \
        -d "client_id=$client_id" \
        -d "client_secret=$client_secret" \
        -d "scope=openid" 2>/dev/null)

    local token=$(echo "$response" | jq -r '.access_token // empty' 2>/dev/null)
    local expires_in=$(echo "$response" | jq -r '.expires_in // 3600' 2>/dev/null)

    if [[ -n "$token" ]]; then
        local expires=$((now + expires_in - 60))  # 60s buffer
        mkdir -p "$(dirname "$cache_file")"
        echo "${token}|${expires}" > "$cache_file"
        chmod 600 "$cache_file"
        echo "$token"
        return 0
    fi

    return 1
}

_llm_complete() {
    local cmd="$READLINE_LINE"
    _llm_debug "=== _llm_complete called ==="
    _llm_debug "Input: $cmd"

    # Skip if empty
    [[ -z "$cmd" ]] && { _llm_debug "Empty input, skipping"; return; }

    # Get auth token
    local token=$(_llm_get_token)
    if [[ -z "$token" ]]; then
        _llm_debug "Failed to get token"
        return
    fi
    _llm_debug "Token acquired"

    # Build context-aware prompt
    local context="PWD: $PWD"

    # Add recent command history
    local recent_history=$(history 5 2>/dev/null | tail -5 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//' | tr '\n' '; ')
    [[ -n "$recent_history" ]] && context="$context
Recent commands: $recent_history"

    # Add git context if in repo
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        local branch=$(git branch --show-current 2>/dev/null)
        local status=$(git status --porcelain 2>/dev/null | head -3)
        context="$context
Git branch: $branch"
        [[ -n "$status" ]] && context="$context
Git status:
$status"
    fi

    local system_prompt="You are a bash command assistant.
Convert input to a complete bash command:
- Partial command: 'git st' -> 'git status'
- Natural language: '# show files' -> 'ls -la'
- Japanese: '# gitの状態' -> 'git status'
Output ONLY the complete command. No explanations, no markdown, no quotes.
Context: $context"

    local response=$(curl -s --max-time "$LLM_COMPLETE_TIMEOUT" \
        "$LLM_COMPLETE_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        -d "$(jq -n \
            --arg system "$system_prompt" \
            --arg user "$cmd" \
            --arg model "$LLM_COMPLETE_MODEL" \
            '{
                model: $model,
                messages: [
                    {role: "system", content: $system},
                    {role: "user", content: $user}
                ],
                max_tokens: 128,
                temperature: 0.1
            }')" 2>/dev/null)

    _llm_debug "Raw response: $response"
    response=$(echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    _llm_debug "Parsed response: $response"

    if [[ -n "$response" ]]; then
        local cleaned=""
        # Try to extract command from ```bash ... ``` block
        cleaned=$(echo "$response" | sed -n '/^```/,/^```/{ /^```/d; p; }' | head -1)
        # If no code block, use first non-empty line
        if [[ -z "$cleaned" ]]; then
            cleaned=$(echo "$response" | grep -v '^```' | grep -v '^$' | head -1)
        fi
        # Remove inline backticks
        cleaned="${cleaned#\`}"
        cleaned="${cleaned%\`}"
        # Trim whitespace
        cleaned=$(echo "$cleaned" | xargs 2>/dev/null || echo "$cleaned")

        _llm_debug "Cleaned response: $cleaned"

        if [[ -n "$cleaned" ]]; then
            READLINE_LINE="$cleaned"
            READLINE_POINT=${#READLINE_LINE}
        fi
    fi
}

# Error fix function (:e in vi-command mode)
# Suggests fix for the last failed command
_llm_error_fix() {
    # Get last command and its exit status
    local last_cmd=$(history 1 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')
    # Prefer starship's exit code (more reliable), fallback to our var
    local last_exit=${STARSHIP_CMD_STATUS:-${_LLM_LAST_EXIT:-0}}

    _llm_debug "=== _llm_error_fix called ==="
    _llm_debug "Last command: $last_cmd"
    _llm_debug "Last exit code: $last_exit (LLM=$_LLM_LAST_EXIT, STARSHIP=$STARSHIP_CMD_STATUS)"

    # Skip if last command succeeded
    if [[ "$last_exit" == "0" ]]; then
        echo -e "\033[32m✓ Last command succeeded (exit 0)\033[0m"
        return
    fi

    echo -e "\033[33m🔧 Fixing: $last_cmd (exit $last_exit)\033[0m"

    local token=$(_llm_get_token)
    if [[ -z "$token" ]]; then
        echo -e "\033[31m✗ Failed to get auth token\033[0m"
        return
    fi

    local system_prompt="You are a bash error fixer.
The user ran a command that failed. Suggest the corrected command.
Output ONLY the fixed command. No explanations.
Examples:
- 'gti status' (typo) -> 'git status'
- 'cd /nonexistent' (path error) -> suggest valid path or 'mkdir -p /nonexistent && cd /nonexistent'"

    local user_prompt="Failed command: $last_cmd
Exit code: $last_exit
PWD: $PWD"

    local response=$(curl -s --max-time "$LLM_COMPLETE_TIMEOUT" \
        "$LLM_COMPLETE_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        -d "$(jq -n \
            --arg system "$system_prompt" \
            --arg user "$user_prompt" \
            --arg model "$LLM_COMPLETE_MODEL" \
            '{
                model: $model,
                messages: [
                    {role: "system", content: $system},
                    {role: "user", content: $user}
                ],
                max_tokens: 128,
                temperature: 0.1
            }')" 2>/dev/null | jq -r '.choices[0].message.content // empty' 2>/dev/null)

    _llm_debug "Error fix response: $response"

    if [[ -n "$response" ]]; then
        # Clean up response
        local cleaned=$(echo "$response" | sed -n '/^```/,/^```/{ /^```/d; p; }' | head -1)
        if [[ -z "$cleaned" ]]; then
            cleaned=$(echo "$response" | grep -v '^```' | grep -v '^$' | head -1)
        fi
        cleaned="${cleaned#\`}"
        cleaned="${cleaned%\`}"
        cleaned=$(echo "$cleaned" | xargs 2>/dev/null || echo "$cleaned")

        if [[ -n "$cleaned" ]]; then
            READLINE_LINE="$cleaned"
            READLINE_POINT=${#READLINE_LINE}
        fi
    else
        echo -e "\033[31m✗ No fix suggested\033[0m"
    fi
}

# Pipe completion function (auto-triggered when line ends with |)
# Suggests next command in pipeline based on context
_llm_pipe_complete() {
    local cmd="$READLINE_LINE"

    # Only trigger if line ends with | or | followed by space
    [[ "$cmd" != *"|"* ]] && return
    [[ "$cmd" != *"|" && "$cmd" != *"| " ]] && {
        _llm_complete
        return
    }

    local token=$(_llm_get_token)
    [[ -z "$token" ]] && return

    # Get recent history for context
    local recent_history=$(history 10 | tail -10 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//' | tr '\n' '; ')

    local system_prompt="You are a bash pipeline assistant.
The user is building a pipeline. Suggest the next command to pipe to.
Output ONLY the command to add after the pipe. No explanations.
Examples:
- 'cat file.txt |' -> 'grep pattern'
- 'ps aux |' -> 'grep process_name'
- 'ls -la |' -> 'head -20'
Consider the recent command history for context."

    local user_prompt="Current command: $cmd
PWD: $PWD
Recent commands: $recent_history"

    local response=$(curl -s --max-time "$LLM_COMPLETE_TIMEOUT" \
        "$LLM_COMPLETE_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        -d "$(jq -n \
            --arg system "$system_prompt" \
            --arg user "$user_prompt" \
            --arg model "$LLM_COMPLETE_MODEL" \
            '{
                model: $model,
                messages: [
                    {role: "system", content: $system},
                    {role: "user", content: $user}
                ],
                max_tokens: 64,
                temperature: 0.1
            }')" 2>/dev/null | jq -r '.choices[0].message.content // empty' 2>/dev/null)

    if [[ -n "$response" ]]; then
        response="${response#\`}"
        response="${response%\`}"
        # Append to current line (after the pipe)
        if [[ "$cmd" == *"| " ]]; then
            READLINE_LINE="${cmd}${response}"
        else
            READLINE_LINE="${cmd} ${response}"
        fi
        READLINE_POINT=${#READLINE_LINE}
    fi
}

# Note: Exit status is captured by _llm_capture_exit in bashrc.nix
# Works with both starship (via starship_precmd_user_func) and vanilla bash (via PROMPT_COMMAND)

# Override _llm_complete to handle pipe case
_llm_complete_wrapper() {
    local cmd="$READLINE_LINE"
    if [[ "$cmd" == *"|" || "$cmd" == *"| " ]]; then
        _llm_pipe_complete
    else
        _llm_complete
    fi
}

# Command explanation (Ctrl+X)
_llm_explain() {
    local cmd="$READLINE_LINE"
    [[ -z "$cmd" ]] && return

    local token=$(_llm_get_token)
    [[ -z "$token" ]] && return

    local system_prompt="You are a bash command explainer.
Explain what the command does in simple terms.
Reply in the same language as the command context (Japanese if Japanese detected).
Keep it concise (1-2 lines)."

    local response=$(curl -s --max-time "$LLM_COMPLETE_TIMEOUT" \
        "$LLM_COMPLETE_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        -d "$(jq -n \
            --arg system "$system_prompt" \
            --arg user "Explain: $cmd" \
            --arg model "$LLM_COMPLETE_MODEL" \
            '{
                model: $model,
                messages: [
                    {role: "system", content: $system},
                    {role: "user", content: $user}
                ],
                max_tokens: 128,
                temperature: 0.3
            }')" 2>/dev/null | jq -r '.choices[0].message.content // empty' 2>/dev/null)

    if [[ -n "$response" ]]; then
        # Display explanation below prompt
        echo ""
        echo -e "\033[36m💡 $response\033[0m"
    fi
}

# Cheatsheet (Ctrl+/)
_llm_cheatsheet() {
    local cmd="$READLINE_LINE"
    local tool="${cmd%% *}"  # First word
    [[ -z "$tool" ]] && tool="bash"

    local token=$(_llm_get_token)
    [[ -z "$token" ]] && return

    local system_prompt="You are a CLI cheatsheet generator.
Show 5-7 most useful commands for the given tool.
Format: one command per line, with brief comment.
No markdown, no explanations, just commands."

    local response=$(curl -s --max-time "$LLM_COMPLETE_TIMEOUT" \
        "$LLM_COMPLETE_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        -d "$(jq -n \
            --arg system "$system_prompt" \
            --arg user "Cheatsheet for: $tool" \
            --arg model "$LLM_COMPLETE_MODEL" \
            '{
                model: $model,
                messages: [
                    {role: "system", content: $system},
                    {role: "user", content: $user}
                ],
                max_tokens: 256,
                temperature: 0.3
            }')" 2>/dev/null | jq -r '.choices[0].message.content // empty' 2>/dev/null)

    if [[ -n "$response" ]]; then
        echo ""
        echo -e "\033[33m📋 $tool cheatsheet:\033[0m"
        echo "$response" | head -10
    fi
}

# Execution preview (Ctrl+P)
_llm_preview() {
    local cmd="$READLINE_LINE"
    [[ -z "$cmd" ]] && return

    local token=$(_llm_get_token)
    [[ -z "$token" ]] && return

    # Get actual file list for commands like rm, mv, cp
    local preview_info=""
    if [[ "$cmd" == rm* || "$cmd" == mv* || "$cmd" == cp* ]]; then
        # Extract glob pattern and expand it
        local pattern=$(echo "$cmd" | sed 's/^[^ ]* //' | sed 's/ .*//')
        local files=$(ls -1 $pattern 2>/dev/null | head -10)
        local count=$(ls -1 $pattern 2>/dev/null | wc -l)
        [[ -n "$files" ]] && preview_info="Matching files ($count total): $files"
    fi

    local system_prompt="You are a command preview assistant.
Describe what will happen when this command runs.
Include: affected files/dirs, potential risks, side effects.
Be concise (2-3 lines). Warn if dangerous."

    local user_prompt="Preview: $cmd
PWD: $PWD"
    [[ -n "$preview_info" ]] && user_prompt="$user_prompt
$preview_info"

    local response=$(curl -s --max-time "$LLM_COMPLETE_TIMEOUT" \
        "$LLM_COMPLETE_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        -d "$(jq -n \
            --arg system "$system_prompt" \
            --arg user "$user_prompt" \
            --arg model "$LLM_COMPLETE_MODEL" \
            '{
                model: $model,
                messages: [
                    {role: "system", content: $system},
                    {role: "user", content: $user}
                ],
                max_tokens: 128,
                temperature: 0.3
            }')" 2>/dev/null | jq -r '.choices[0].message.content // empty' 2>/dev/null)

    if [[ -n "$response" ]]; then
        echo ""
        echo -e "\033[35m🔍 Preview:\033[0m"
        echo "$response"
    fi
}

# Status/Help display (:? in vi-command mode)
_llm_status() {
    echo ""
    echo -e "\033[1;36m═══ LLM Bash Completion Status ═══\033[0m"
    echo ""

    # Configuration
    echo -e "\033[1;33m📋 Configuration:\033[0m"
    echo "  LLM_COMPLETE_URL     = ${LLM_COMPLETE_URL:-\033[31m(not set)\033[0m}"
    echo "  LLM_COMPLETE_MODEL   = ${LLM_COMPLETE_MODEL:-\033[31m(not set)\033[0m}"
    echo "  LLM_COMPLETE_TIMEOUT = ${LLM_COMPLETE_TIMEOUT:-5}s"
    echo "  LLM_DEBUG            = ${LLM_DEBUG:-0}"
    [[ "$LLM_DEBUG" == "1" ]] && echo "  LLM_DEBUG_LOG        = $LLM_DEBUG_LOG"
    echo ""

    # Auth config
    echo -e "\033[1;33m🔐 Authentication:\033[0m"
    echo "  LLM_TOKEN_URL        = ${LLM_TOKEN_URL:-\033[31m(not set)\033[0m}"
    echo "  LLM_CLIENT_ID_PATH   = $LLM_CLIENT_ID_PATH"
    echo "  LLM_CLIENT_SECRET_PATH = $LLM_CLIENT_SECRET_PATH"
    echo ""

    # Token cache status
    echo -e "\033[1;33m🎫 Token Cache:\033[0m"
    local cache_file="${LLM_TOKEN_CACHE:-$HOME/.cache/llm-complete-token}"
    if [[ -f "$cache_file" ]]; then
        local cached=$(cat "$cache_file" 2>/dev/null)
        local expires=$(echo "$cached" | cut -d'|' -f2)
        local now=$(date +%s)
        if [[ -n "$expires" && "$now" -lt "$expires" ]]; then
            local remaining=$((expires - now))
            echo -e "  Status: \033[32m✓ Valid\033[0m (expires in ${remaining}s)"
        else
            echo -e "  Status: \033[31m✗ Expired\033[0m"
        fi
    else
        echo -e "  Status: \033[33m○ No cached token\033[0m"
    fi
    echo ""

    # Passage credentials check
    echo -e "\033[1;33m🔑 Credentials (passage):\033[0m"
    if command -v passage &>/dev/null; then
        if passage show "$LLM_CLIENT_ID_PATH" &>/dev/null; then
            echo -e "  Client ID:     \033[32m✓ Found\033[0m"
        else
            echo -e "  Client ID:     \033[31m✗ Not found\033[0m at $LLM_CLIENT_ID_PATH"
        fi
        if passage show "$LLM_CLIENT_SECRET_PATH" &>/dev/null; then
            echo -e "  Client Secret: \033[32m✓ Found\033[0m"
        else
            echo -e "  Client Secret: \033[31m✗ Not found\033[0m at $LLM_CLIENT_SECRET_PATH"
        fi
    else
        echo -e "  \033[31m✗ passage command not found\033[0m"
    fi
    echo ""

    # Keybindings
    echo -e "\033[1;33m⌨️  Keybindings (vi-command mode):\033[0m"
    echo "  ::  Command completion / pipe completion"
    echo "  :e  Fix last failed command"
    echo "  :x  Explain command"
    echo "  :c  Cheatsheet"
    echo "  :p  Preview execution"
    echo "  :h  History search (natural language)"
    echo "  :?  This status screen"
    echo ""

    # Connection test
    echo -e "\033[1;33m🌐 Connection Test:\033[0m"
    local test_url="${LLM_COMPLETE_URL}/health"
    if curl -s --max-time 3 "$test_url" &>/dev/null; then
        echo -e "  API Health: \033[32m✓ Reachable\033[0m"
    else
        echo -e "  API Health: \033[31m✗ Unreachable\033[0m ($test_url)"
    fi
    echo ""
}

# Natural language history search (Ctrl+R replacement)
_llm_history_search() {
    local query="$READLINE_LINE"
    [[ -z "$query" ]] && return

    local token=$(_llm_get_token)
    [[ -z "$token" ]] && return

    # Get recent history
    local history_data=$(history 100 | tail -100 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')

    local system_prompt="You are a command history search assistant.
Find the most relevant command from history that matches the user's description.
Output ONLY the matching command, nothing else.
If no match found, output nothing."

    local response=$(curl -s --max-time "$LLM_COMPLETE_TIMEOUT" \
        "$LLM_COMPLETE_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        -d "$(jq -n \
            --arg system "$system_prompt" \
            --arg user "Query: $query
History:
$history_data" \
            --arg model "$LLM_COMPLETE_MODEL" \
            '{
                model: $model,
                messages: [
                    {role: "system", content: $system},
                    {role: "user", content: $user}
                ],
                max_tokens: 128,
                temperature: 0.1
            }')" 2>/dev/null | jq -r '.choices[0].message.content // empty' 2>/dev/null)

    if [[ -n "$response" ]]; then
        response="${response#\`}"
        response="${response%\`}"
        READLINE_LINE="$response"
        READLINE_POINT=${#READLINE_LINE}
    fi
}
