#!/usr/bin/env bash
# Collect the report date's GitHub events for the configured user, emitted as
# raw filtered JSON objects (one per line). Interpret the output by event type:
#   PushEvent                        -> repo, branch, commit messages (.payload.commits[].message)
#   PullRequestReviewEvent /
#   PullRequestReviewCommentEvent    -> repo, PR title
#   PullRequestEvent                 -> opened/merged PRs
#   CreateEvent / DeleteEvent        -> branch lifecycle
#
# The events feed only reaches back ~90 days and ~300 events, whichever comes
# first, so a far-past date can come back empty even on a busy day. A heavy
# committer runs out of events long before the 90 days.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"

GITHUB_USER=$(jq -r '.sources.github.user' "$CONFIG")
START=$(day_start_ts) || exit 1
END=$(day_end_ts)

# created_at is UTC, so compare against the local day's bounds expressed in UTC
# rather than prefix-matching the date — those are the same 24 hours only for a
# machine running on UTC.
FROM=$(utc_iso "$START")
TO=$(utc_iso "$END")

gh api "/users/$GITHUB_USER/events" --paginate \
  -q ".[] | select(.created_at >= \"$FROM\" and .created_at < \"$TO\")" 2>/dev/null
