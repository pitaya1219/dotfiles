#!/usr/bin/env bash
# Syncs secrets between passage (local age-encrypted store) and pass-cli (Proton Pass CLI).
#
# The sync scope is exactly the set of active items in a single, dedicated
# pass-cli vault (default: "Passage"). Each item's title is a passage path,
# verbatim, and its sole field ("value", type hidden) is the secret content
# (1 item = 1 path). This vault must be dedicated to this tool — any other
# item placed in it will be treated as a synced path.
#
# This is a 1-item-per-path design, not 1-item-with-many-fields: pass-cli's
# `item update --field` cannot create Hidden-type fields (new fields always
# land in the item's untyped "extra_fields", invisible to `item view`'s
# structured field listing) and there is no way to add a Hidden field to an
# existing item via the CLI at all — only `item create custom --from-template`
# supports specifying field_type "hidden", and that only creates a brand new
# item. So each path gets its own item: creating it (via --from-template) is
# the only way to get a Hidden field, and updating an already-existing item's
# field preserves whatever type it already has (verified live).
#
# To bring a new path into scope, use `push --path <path>` (registers an
# existing passage value as a new pass-cli item). Otherwise pull/push/sync
# never expand the scope (= the vault's existing item set).
#
# --prefix <namespace> narrows the target to paths where "path == namespace"
# or "path starts with namespace/" (e.g. --prefix address-manager limits the
# sync to paths like address-manager/dev/mssql-sa/id).
#
# Usage:
#   pass-cli-passage-sync.sh pull [--vault NAME] [--prefix NAMESPACE] [--dry-run]
#   pass-cli-passage-sync.sh push [--vault NAME] [--prefix NAMESPACE] [--path PATH]... [--dry-run]
#   pass-cli-passage-sync.sh sync [--vault NAME] [--prefix NAMESPACE] [--prefer passage|pass-cli] [--dry-run]
#   pass-cli-passage-sync.sh list [--vault NAME] [--prefix NAMESPACE]
#
# pull: writes each pass-cli item's value into passage (pass-cli wins, overwrites passage).
# push: writes each passage value into its matching pass-cli item (passage wins, overwrites pass-cli).
#       Use --path <path> to register a not-yet-tracked path.
# sync: bidirectional. Fills in whichever side is missing a path. Where both
#       sides have a path but the values differ, it is reported as a CONFLICT
#       and left untouched by default (use --prefer to pick a resolution side).
# list: prints the passage paths currently tracked in the pass-cli vault (one
#       per line, no values read or shown).
#
# Secret values are never printed or logged — only whether something changed.

set -euo pipefail

VAULT="Passage"
MODE=""
PREFER=""
PREFIX=""
DRY_RUN=0
ADD_PATHS=()

usage() {
  sed -n '2,43p' "$0" | sed 's/^# \{0,1\}//'
}

if [ $# -eq 0 ]; then
  usage >&2
  exit 1
fi

MODE="$1"
shift

while [ $# -gt 0 ]; do
  case "$1" in
    --vault) VAULT="${2:?--vault requires a value}"; shift 2 ;;
    --path) ADD_PATHS+=("${2:?--path requires a path}"); shift 2 ;;
    --prefer) PREFER="${2:?--prefer requires passage or pass-cli}"; shift 2 ;;
    --prefix) PREFIX="${2:?--prefix requires a namespace}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

case "$MODE" in
  pull|push|sync|list) ;;
  *) echo "unknown command: $MODE (expected pull, push, sync, or list)" >&2; exit 1 ;;
esac

if [ -n "$PREFER" ] && [ "$PREFER" != "passage" ] && [ "$PREFER" != "pass-cli" ]; then
  echo "--prefer must be 'passage' or 'pass-cli'" >&2
  exit 1
fi

PREFIX="${PREFIX%/}"

for bin in jq pass-cli passage; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "required command not found: $bin" >&2
    exit 1
  fi
done

# Always matches when --prefix is unset. Otherwise matches only when path is
# exactly the namespace, or starts with "namespace/" (a plain string-prefix
# check would let "foo" false-positive on "foobar/x", so we compare up through
# the separating "/").
prefix_match() {
  local path="$1"
  [ -z "$PREFIX" ] && return 0
  [ "$path" = "$PREFIX" ] && return 0
  case "$path" in
    "$PREFIX"/*) return 0 ;;
  esac
  return 1
}

# Emits one active item title (= passage path) per line from the dedicated vault.
fetch_vault_paths() {
  local json
  if ! json=$(pass-cli item list --vault-name "$VAULT" --filter-state active --output json 2>&1); then
    echo "failed to list items in pass-cli vault '${VAULT}'. Check pass-cli login:" >&2
    echo "$json" >&2
    exit 1
  fi
  printf '%s' "$json" | jq -r '.items[].title'
}

passage_show() {
  passage show "$1" 2>/dev/null
}

passage_write() {
  printf '%s' "$2" | passage insert --echo --force "$1" >/dev/null 2>&1
}

pass_cli_read() {
  pass-cli item view --vault-name "$VAULT" --item-title "$1" --field value 2>/dev/null
}

# Create-or-update: if an item with this title already exists, update its
# "value" field (this preserves the field's existing type — verified live
# that updating an already-Hidden field via `item update --field` keeps it
# Hidden). Otherwise create a fresh item from a template with field_type
# "hidden", piped via stdin so the value never touches argv or disk.
pass_cli_write() {
  local path="$1" value="$2"
  if pass-cli item view --vault-name "$VAULT" --item-title "$path" >/dev/null 2>&1; then
    pass-cli item update --vault-name "$VAULT" --item-title "$path" --field "value=${value}" >/dev/null
  else
    jq -n --arg title "$path" --arg value "$value" \
      '{title: $title, note: "", sections: [{section_name: "secret", fields: [{field_name: "value", field_type: "hidden", value: $value}]}]}' \
      | pass-cli item create custom --vault-name "$VAULT" --from-template - >/dev/null
  fi
}

cmd_pull() {
  local path value current
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    prefix_match "$path" || continue
    value=$(pass_cli_read "$path")
    current=$(passage_show "$path" || true)
    if [ "$current" = "$value" ]; then
      continue
    fi
    if [ "$DRY_RUN" = 1 ]; then
      echo "[dry-run] pull: $path (pass-cli -> passage)"
      continue
    fi
    passage_write "$path" "$value"
    echo "pull: $path updated"
  done < <(fetch_vault_paths)
}

cmd_push() {
  local path value current
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    prefix_match "$path" || continue
    if ! current=$(passage_show "$path"); then
      echo "push: skip $path (not found in passage)" >&2
      continue
    fi
    value=$(pass_cli_read "$path")
    if [ "$current" = "$value" ]; then
      continue
    fi
    if [ "$DRY_RUN" = 1 ]; then
      echo "[dry-run] push: $path (passage -> pass-cli)"
      continue
    fi
    pass_cli_write "$path" "$current"
    echo "push: $path updated"
  done < <(fetch_vault_paths)

  local add_path add_value
  for add_path in "${ADD_PATHS[@]:-}"; do
    [ -z "$add_path" ] && continue
    if ! add_value=$(passage_show "$add_path"); then
      echo "push --path: $add_path not found in passage" >&2
      exit 1
    fi
    if [ "$DRY_RUN" = 1 ]; then
      echo "[dry-run] push --path: $add_path (new item)"
      continue
    fi
    pass_cli_write "$add_path" "$add_value"
    echo "push --path: $add_path registered as a new pass-cli item"
  done
}

cmd_list() {
  local path
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    prefix_match "$path" || continue
    echo "$path"
  done < <(fetch_vault_paths)
}

cmd_sync() {
  local path pc_value pg_value conflicts=0
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    prefix_match "$path" || continue
    pc_value=$(pass_cli_read "$path")
    if ! pg_value=$(passage_show "$path"); then
      if [ "$DRY_RUN" = 1 ]; then
        echo "[dry-run] sync: $path (pull, missing in passage)"
        continue
      fi
      passage_write "$path" "$pc_value"
      echo "sync: $path pulled (was missing in passage)"
      continue
    fi

    if [ "$pg_value" = "$pc_value" ]; then
      continue
    fi

    case "$PREFER" in
      passage)
        if [ "$DRY_RUN" = 1 ]; then
          echo "[dry-run] sync: $path (push, --prefer=passage)"
          continue
        fi
        pass_cli_write "$path" "$pg_value"
        echo "sync: $path pushed (--prefer=passage)"
        ;;
      pass-cli)
        if [ "$DRY_RUN" = 1 ]; then
          echo "[dry-run] sync: $path (pull, --prefer=pass-cli)"
          continue
        fi
        passage_write "$path" "$pc_value"
        echo "sync: $path pulled (--prefer=pass-cli)"
        ;;
      *)
        echo "CONFLICT: $path differs between passage and pass-cli (left untouched). Resolve with --prefer passage|pass-cli, or push/pull it individually" >&2
        conflicts=1
        ;;
    esac
  done < <(fetch_vault_paths)

  if [ "$conflicts" = 1 ]; then
    echo "sync: unresolved conflicts remain" >&2
    exit 1
  fi
}

case "$MODE" in
  pull) cmd_pull ;;
  push) cmd_push ;;
  sync) cmd_sync ;;
  list) cmd_list ;;
esac
