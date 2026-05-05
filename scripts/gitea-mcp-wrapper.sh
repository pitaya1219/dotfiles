#!/bin/bash
# Gitea MCP wrapper to load environment from direnv and run gitea-mcp
# Uses current working directory as project root

# Use direnv exec to load .envrc from current directory
exec direnv exec . bash -c '
    export GITEA_ACCESS_TOKEN="${GITEA_VIBE_BOT_TOKEN:-$GITEA_ACCESS_TOKEN}"
    export GITEA_HOST="${GITEA_HOST:-https://git.pitaya.f5.si}"
    exec gitea-mcp "$@"
' -- "$@"
