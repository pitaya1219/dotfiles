#!/usr/bin/env bash
# Self-contained tests for `task sync:logseq:_shrink_check` (tasks/sync/logseq.yml).
#
# Each test builds a fixture in its own tmp dir: logseq/{journals,pages} as
# the "post-sync" local state, and backups/<gen>/{journals,pages} as the
# "pre-sync" snapshot (plus backups/.last pointing at it, mirroring what
# sync:logseq:_backup writes). It then invokes the real task target and
# inspects the generated conflict-*.md page and log output.
#
# Notification suppression: sync:logseq:notify pops a real OS notification
# (osascript on macOS, termux-notification, notify-send elsewhere). Every
# task invocation below exports LOGSEQ_SYNC_NO_NOTIFY=1, which notify checks
# first and exits on before touching the OS - see tasks/sync/logseq.yml.
# This still exercises the "would have notified" code path in _shrink_check
# without actually popping anything during test runs.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

TEST_MACHINE_NAME="testhost"

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

# Build a fresh fixture root with an empty logseq/{journals,pages} tree and
# a single backup generation (also empty) pointed at by backups/.last.
# Returns the root path on stdout.
new_fixture() {
    local root
    root=$(mktemp -d "${TMPDIR:-/tmp}/shrink_check_test.XXXXXX")
    mkdir -p "$root/logseq/journals" "$root/logseq/pages"
    mkdir -p "$root/backups/20260813_090000/journals" "$root/backups/20260813_090000/pages"
    echo "$root/backups/20260813_090000" >"$root/backups/.last"
    echo "$root"
}

# Run the real task target against a fixture root, capturing combined
# output to $root/task_output.log for failure diagnostics.
run_shrink_check() {
    local root="$1"
    (
        cd "$REPO_ROOT" &&
            LOGSEQ_SYNC_NO_NOTIFY=1 SYNC_MACHINE_NAME="$TEST_MACHINE_NAME" \
            task sync:logseq:_shrink_check \
                LOGSEQ_LOCAL="$root/logseq" \
                BACKUP_DIR="$root/backups" \
                LOG_FILE="$root/log.txt"
    ) >"$root/task_output.log" 2>&1
}

# The report filename the task will use for the first report today about the
# given original basename (no extension) - conflict-<machine>-<today>-<name>.md.
conflict_page_path() {
    local root="$1" name="$2" today
    today=$(date '+%Y-%m-%d')
    echo "$root/logseq/pages/conflict-${TEST_MACHINE_NAME}-${today}-${name}.md"
}

# --- Test 1: drastic shrink -> conflict page generated ---
test_drastic_shrink() {
    local name="drastic_shrink"
    local root
    root=$(new_fixture)
    cleanup_roots+=("$root")

    printf 'This is a fairly long journal entry, long enough to clear the min-bytes floor easily.\n' \
        >"$root/backups/20260813_090000/journals/2026_08_13.md"
    printf '' >"$root/logseq/journals/2026_08_13.md"

    if ! run_shrink_check "$root"; then
        log_fail "$name" "task invocation failed, see $root/task_output.log"
        return
    fi

    local page
    page=$(conflict_page_path "$root" "2026-08-13")
    if [[ -f "$page" ]] && grep -q "shrank from" "$page" && grep -q "# Conflict detected: \[\[2026_08_13\]\]" "$page"; then
        log_pass "$name"
    else
        log_fail "$name" "expected conflict page at $page with shrink content, see $root/task_output.log"
    fi
}

# --- Test 2: unchanged / normal edits (grew, minor shrink) -> no conflict page ---
test_no_false_positive() {
    local name="no_false_positive_normal_edits"
    local root
    root=$(new_fixture)
    cleanup_roots+=("$root")

    # Unchanged.
    printf 'unchanged content, identical before and after, comfortably above the floor.\n' \
        >"$root/backups/20260813_090000/journals/unchanged.md"
    cp "$root/backups/20260813_090000/journals/unchanged.md" "$root/logseq/journals/unchanged.md"

    # Grew (normal editing).
    printf 'short seed line above the floor already, some content here.\n' \
        >"$root/backups/20260813_090000/journals/grew.md"
    printf 'short seed line above the floor already, some content here.\nplus a lot more added later.\n' \
        >"$root/logseq/journals/grew.md"

    # Minor shrink (well under the 50%% ratio threshold - trimmed a line, not lost update).
    printf 'line one is here\nline two is here\nline three is here\nline four is here\n' \
        >"$root/backups/20260813_090000/journals/minor_shrink.md"
    printf 'line one is here\nline two is here\nline three is here\n' \
        >"$root/logseq/journals/minor_shrink.md"

    if ! run_shrink_check "$root"; then
        log_fail "$name" "task invocation failed, see $root/task_output.log"
        return
    fi

    if compgen -G "$root/logseq/pages/conflict-*.md" >/dev/null 2>&1; then
        log_fail "$name" "unexpected conflict page(s) created, see $root/task_output.log"
    else
        log_pass "$name"
    fi
}

# --- Test 3: file deleted after sync (after=0, file absent) -> detected ---
test_deleted_file_detected() {
    local name="deleted_file_detected"
    local root
    root=$(new_fixture)
    cleanup_roots+=("$root")

    printf 'this page had real content before the sync ran and lost it entirely.\n' \
        >"$root/backups/20260813_090000/pages/deleted_page.md"
    # No corresponding file under logseq/pages at all.

    if ! run_shrink_check "$root"; then
        log_fail "$name" "task invocation failed, see $root/task_output.log"
        return
    fi

    local page
    page=$(conflict_page_path "$root" "deleted-page")
    if [[ -f "$page" ]] && grep -q "shrank from" "$page"; then
        log_pass "$name"
    else
        log_fail "$name" "expected a conflict page for deleted-page, see $root/task_output.log"
    fi
}

# --- Test 4: before < SHRINK_MIN_BYTES -> not detected even though emptied ---
test_below_min_bytes_ignored() {
    local name="below_min_bytes_ignored"
    local root
    root=$(new_fixture)
    cleanup_roots+=("$root")

    # 20 bytes, under the default 64-byte floor.
    printf 'tiny stub content\n' >"$root/backups/20260813_090000/journals/tiny.md"
    printf '' >"$root/logseq/journals/tiny.md"

    if ! run_shrink_check "$root"; then
        log_fail "$name" "task invocation failed, see $root/task_output.log"
        return
    fi

    if compgen -G "$root/logseq/pages/conflict-*.md" >/dev/null 2>&1; then
        log_fail "$name" "unexpected conflict page for a sub-floor file, see $root/task_output.log"
    else
        log_pass "$name"
    fi
}

# --- Test 5: pre-existing conflict page for the same basename -> appended, not overwritten ---
test_existing_conflict_page_appended() {
    local name="existing_conflict_page_appended"
    local root
    root=$(new_fixture)
    cleanup_roots+=("$root")

    printf 'This journal entry is long enough to clear the floor and then gets emptied out.\n' \
        >"$root/backups/20260813_090000/journals/2026_08_13.md"
    printf '' >"$root/logseq/journals/2026_08_13.md"

    local page
    page=$(conflict_page_path "$root" "2026-08-13")
    cat >"$page" <<'EOF'
tags:: #conflict
created:: 2026-08-13 08:00:00

# Conflict detected: [[2026_08_13]]

PRE_EXISTING_MARKER_DO_NOT_LOSE_ME
EOF

    if ! run_shrink_check "$root"; then
        log_fail "$name" "task invocation failed, see $root/task_output.log"
        return
    fi

    if grep -q "PRE_EXISTING_MARKER_DO_NOT_LOSE_ME" "$page" && grep -q "## Shrink detected:" "$page"; then
        log_pass "$name"
    else
        log_fail "$name" "expected original content preserved and a Shrink detected section appended to $page"
    fi
}

# --- Test 6: filenames with spaces and Japanese characters don't break the loop ---
test_unicode_and_spaces_filename() {
    local name="unicode_and_spaces_filename"
    local root
    root=$(new_fixture)
    cleanup_roots+=("$root")

    local fname='会議録 2026-08-13 [[電力Hub]]定例.md'
    printf 'この会議の議事録は同期前に十分な長さの内容を持っていた、というテスト用の文章です。\n' \
        >"$root/backups/20260813_090000/pages/$fname"
    printf '' >"$root/logseq/pages/$fname"

    if ! run_shrink_check "$root"; then
        log_fail "$name" "task invocation failed, see $root/task_output.log"
        return
    fi

    local page_count
    page_count=$(find "$root/logseq/pages" -name 'conflict-*.md' 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$page_count" == "1" ]]; then
        local page
        page=$(find "$root/logseq/pages" -name 'conflict-*.md')
        if grep -q "shrank from" "$page"; then
            log_pass "$name"
        else
            log_fail "$name" "conflict page $page missing expected content"
        fi
    else
        log_fail "$name" "expected exactly 1 conflict page, found $page_count, see $root/task_output.log"
    fi
}

echo "Running shrink_check_test.sh against $REPO_ROOT"
echo

# --- Test 7: a shrunk conflict page is a sync artifact -> no report about it ---
test_conflict_page_not_reported() {
    local name="conflict_page_not_reported"
    local root
    root=$(new_fixture)
    cleanup_roots+=("$root")

    printf 'A conflict page long enough to clear the min-bytes floor before it gets emptied.\n' \
        >"$root/backups/20260813_090000/pages/conflict-2026-08-13.md"
    printf '' >"$root/logseq/pages/conflict-2026-08-13.md"

    if ! run_shrink_check "$root"; then
        log_fail "$name" "task invocation failed, see $root/task_output.log"
        return
    fi

    if [[ -e "$root/logseq/pages/conflict-conflict-2026-08-13.md" ]]; then
        log_fail "$name" "shrunk conflict page produced a conflict-conflict page"
    else
        log_pass "$name"
    fi
}

# --- Test 8: a shrunk *.partial leftover is a sync artifact -> no report about it ---
test_partial_file_not_reported() {
    local name="partial_file_not_reported"
    local root
    root=$(new_fixture)
    cleanup_roots+=("$root")

    # _conflict's "restore the base from the largest copy" step re-adds a .md
    # suffix to a partial leftover, which is how one lands in the tree looking
    # like a page. That is the shape the shrink check has to ignore.
    local leftover="2026_08_13.md.64270ff0.partial.md"
    printf 'An rclone partial long enough to clear the min-bytes floor before it gets emptied.\n' \
        >"$root/backups/20260813_090000/journals/$leftover"
    printf '' >"$root/logseq/journals/$leftover"

    if ! run_shrink_check "$root"; then
        log_fail "$name" "task invocation failed, see $root/task_output.log"
        return
    fi

    if compgen -G "$root/logseq/pages/conflict-*partial*" >/dev/null 2>&1; then
        log_fail "$name" "shrunk partial leftover produced a conflict page"
    else
        log_pass "$name"
    fi
}

test_drastic_shrink
test_no_false_positive
test_deleted_file_detected
test_below_min_bytes_ignored
test_existing_conflict_page_appended
test_unicode_and_spaces_filename
test_conflict_page_not_reported
test_partial_file_not_reported

echo
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    echo "Failures:"
    printf '  - %s\n' "${FAILURES[@]}"
    exit 1
fi
exit 0
