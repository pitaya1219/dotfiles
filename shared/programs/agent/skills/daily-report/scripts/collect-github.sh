#!/usr/bin/env bash
# Collect today's GitHub events for the configured user, emitted as raw filtered
# JSON objects (one per line). Interpret the output by event type:
#   PushEvent                        -> repo, branch, commit messages (.payload.commits[].message)
#   PullRequestReviewEvent /
#   PullRequestReviewCommentEvent    -> repo, PR title
#   PullRequestEvent                 -> opened/merged PRs
#   CreateEvent / DeleteEvent        -> branch lifecycle
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"

GITHUB_USER=$(jq -r '.sources.github.user' "$CONFIG")
TODAY=$(today)

gh api "/users/$GITHUB_USER/events" --paginate \
  -q ".[] | select(.created_at | startswith(\"$TODAY\"))" 2>/dev/null
