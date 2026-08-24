#!/usr/bin/env bash
# Self-contained tests for `task sync:logseq:_conflict` (tasks/sync/logseq.yml).
#
# Each test builds a fixture in its own tmp dir holding logseq/{journals,pages}
# with the `*.conflict*` copies rclone bisync leaves behind, invokes the real
# task target, then inspects which pages were written and which copies were
# removed.
#
# Notification suppression: _conflict calls sync:logseq:notify when it finds
# anything. Every task invocation below exports LOGSEQ_SYNC_NO_NOTIFY=1, which
# notify checks first and exits on before touching the OS - see
# tasks/sync/logseq.yml.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

PASS=0
FAIL=0
FAILURES=()

log_pass() {
    PASS=$((PASS + 1))
    echo "PASS: $1"
}

log_fail() {
    FAIL=$((FAIL + 1))
    FAILURES+=("$1")
    echo "FAIL: $1"
    if [[ -n "${2:-}" ]]; then
        echo "  -> $2"
    fi
}

cleanup_roots=()
cleanup() {
    local r
    for r in "${cleanup_roots[@]:-}"; do
        [[ -n "$r" && -d "$r" ]] && rm -rf "$r"
    done
}
trap cleanup EXIT

# Build a fresh fixture root with an empty logseq/{journals,pages} tree.
# Returns the root path on stdout.
new_fixture() {
    local root
    root=$(mktemp -d "${TMPDIR:-/tmp}/conflict_test.XXXXXX")
    mkdir -p "$root/logseq/journals" "$root/logseq/pages"
    echo "$root"
}

# Run the real task target against a fixture root, capturing combined
# output to $root/task_output.log for failure diagnostics.
run_conflict() {
    local root="$1"
    (
        cd "$REPO_ROOT" &&
            LOGSEQ_SYNC_NO_NOTIFY=1 task sync:logseq:_conflict \
                LOGSEQ_LOCAL="$root/logseq" \
                LOG_FILE="$root/log.txt"
    ) >"$root/task_output.log" 2>&1
}

# --- Test 1: an ordinary page conflict still produces a conflict page ---
test_ordinary_conflict_reported() {
    local name="ordinary_conflict_reported"
    local root
    root=$(new_fixture)
    cleanup_roots+=("$root")

    printf -- '- current content\n' >"$root/logseq/journals/2026_08_13.md"
    local copy="$root/logseq/journals/2026_08_13.md.conflict-2026-08-14-1"
    printf -- '- older content\n' >"$copy"

    if ! run_conflict "$root"; then
        log_fail "$name" "task invocation failed, see $root/task_output.log"
        return
    fi

    local page="$root/logseq/pages/conflict-2026-08-13.md"
    if [[ -f "$page" ]] &&
        grep -q '# Conflict detected: \[\[2026_08_13\]\]' "$page" &&
        grep -q 'older content' "$page" &&
        grep -q 'current content' "$page" &&
        [[ ! -e "$copy" ]]; then
        log_pass "$name"
    else
        log_fail "$name" "expected a conflict page holding both versions and the copy removed, see $root/task_output.log"
    fi
}

# --- Test 2: a conflicting conflict page is dropped, not appended to ---
# The append this replaces fed each round's diff its own previous output, so
# the page grew by roughly its own size every round.
test_conflict_page_dropped_without_append() {
    local name="conflict_page_dropped_without_append"
    local root
    root=$(new_fixture)
    cleanup_roots+=("$root")

    local page="$root/logseq/pages/conflict-2026-08-13.md"
    printf -- 'tags:: #conflict\n\nPRE_EXISTING_MARKER_DO_NOT_LOSE_ME\n' >"$page"
    local copy="$root/logseq/pages/conflict-2026-08-13.md.conflict-2026-08-14-1"
    printf -- 'tags:: #conflict\n\na diverged copy from another device\n' >"$copy"

    if ! run_conflict "$root"; then
        log_fail "$name" "task invocation failed, see $root/task_output.log"
        return
    fi

    if ! grep -q 'PRE_EXISTING_MARKER_DO_NOT_LOSE_ME' "$page"; then
        log_fail "$name" "the existing conflict page lost its content"
    elif grep -q 'Re-conflict detected' "$page"; then
        log_fail "$name" "a re-conflict section was appended to $page"
    elif [[ -e "$root/logseq/pages/conflict-conflict-2026-08-13.md" ]]; then
        log_fail "$name" "a conflict-conflict page was generated"
    elif [[ -e "$copy" ]]; then
        log_fail "$name" "the conflict copy was left behind and will re-sync forever"
    else
        log_pass "$name"
    fi
}

# --- Test 3: a *.partial leftover is dropped rather than reported on ---
test_partial_leftover_dropped() {
    local name="partial_leftover_dropped"
    local root
    root=$(new_fixture)
    cleanup_roots+=("$root")

    local leftover="$root/logseq/pages/2026_08_13.md.64270ff0.partial.md"
    printf -- 'a half-transferred body\n' >"$leftover"
    local copy="$root/logseq/pages/2026_08_13.md.64270ff0.partial.md.conflict-2026-08-14-1"
    printf -- 'a different half-transferred body\n' >"$copy"

    if ! run_conflict "$root"; then
        log_fail "$name" "task invocation failed, see $root/task_output.log"
        return
    fi

    if compgen -G "$root/logseq/pages/conflict-*partial*" >/dev/null 2>&1; then
        log_fail "$name" "a partial leftover produced a conflict page"
    elif [[ -e "$copy" ]]; then
        log_fail "$name" "the conflict copy was left behind and will re-sync forever"
    else
        log_pass "$name"
    fi
}

# --- Test 4: identical copies produce no page at all ---
test_identical_copy_produces_no_page() {
    local name="identical_copy_produces_no_page"
    local root
    root=$(new_fixture)
    cleanup_roots+=("$root")

    printf -- '- same content\n' >"$root/logseq/journals/2026_08_13.md"
    local copy="$root/logseq/journals/2026_08_13.md.conflict-2026-08-14-1"
    printf -- '- same content\n' >"$copy"

    if ! run_conflict "$root"; then
        log_fail "$name" "task invocation failed, see $root/task_output.log"
        return
    fi

    if [[ -e "$root/logseq/pages/conflict-2026-08-13.md" ]]; then
        log_fail "$name" "an identical copy still produced a conflict page"
    elif [[ -e "$copy" ]]; then
        log_fail "$name" "the conflict copy was left behind"
    else
        log_pass "$name"
    fi
}

# --- Test 5: a missing base file is restored from the largest copy ---
test_missing_base_restored() {
    local name="missing_base_restored"
    local root
    root=$(new_fixture)
    cleanup_roots+=("$root")

    local base="$root/logseq/journals/2026_08_13.md"
    printf -- '- short\n' >"$root/logseq/journals/2026_08_13.md.conflict-2026-08-14-1"
    printf -- '- the longest surviving copy wins the restore\n' \
        >"$root/logseq/journals/2026_08_13.md.conflict-2026-08-14-2"

    if ! run_conflict "$root"; then
        log_fail "$name" "task invocation failed, see $root/task_output.log"
        return
    fi

    if [[ -f "$base" ]] && grep -q 'longest surviving copy' "$base"; then
        log_pass "$name"
    else
        log_fail "$name" "expected $base restored from the largest copy, see $root/task_output.log"
    fi
}

echo "Running conflict_test.sh against $REPO_ROOT"
echo

test_ordinary_conflict_reported
test_conflict_page_dropped_without_append
test_partial_leftover_dropped
test_identical_copy_produces_no_page
test_missing_base_restored

echo
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    echo "Failures:"
    printf '  - %s\n' "${FAILURES[@]}"
    exit 1
fi
exit 0
