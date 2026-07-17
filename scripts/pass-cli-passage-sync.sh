#!/usr/bin/env bash
# Syncs secrets between passage (local age-encrypted store) and pass-cli (Proton Pass CLI).
#
# The sync scope is exactly the set of fields on a single custom item in a
# single pass-cli vault (default: vault "Passage" / item "passage"). Field
# names match passage paths exactly, and each field's value is the secret
# content itself (1 item = many paths, 1 field = 1 path). This convention was
# introduced by address-manager/scripts/get-secret.sh, so that no separate
# field-name-to-path mapping logic is needed.
#
# To bring a new path into scope, use `push --add <path>` (registers an
# existing passage value as a new pass-cli field). Otherwise pull/push/sync
# never expand the scope (= the pass-cli item's existing field set).
#
# Usage:
#   pass-cli-passage-sync.sh pull [--vault NAME] [--item TITLE] [--dry-run]
#   pass-cli-passage-sync.sh push [--vault NAME] [--item TITLE] [--add PATH]... [--dry-run]
#   pass-cli-passage-sync.sh sync [--vault NAME] [--item TITLE] [--prefer passage|pass-cli] [--dry-run]
#
# pull: writes each pass-cli field's value into passage (pass-cli wins, overwrites passage).
# push: writes each passage value into its matching pass-cli field (passage wins, overwrites pass-cli).
#       Use --add <path> to register a not-yet-tracked path.
# sync: bidirectional. Fills in whichever side is missing a path. Where both
#       sides have a path but the values differ, it is reported as a CONFLICT
#       and left untouched by default (use --prefer to pick a resolution side).
#
# Secret values are never printed or logged — only whether something changed.

set -euo pipefail

VAULT="Passage"
ITEM="passage"
MODE=""
PREFER=""
DRY_RUN=0
ADD_PATHS=()

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
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
    --item) ITEM="${2:?--item requires a value}"; shift 2 ;;
    --add) ADD_PATHS+=("${2:?--add requires a path}"); shift 2 ;;
    --prefer) PREFER="${2:?--prefer requires passage or pass-cli}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

case "$MODE" in
  pull|push|sync) ;;
  *) echo "unknown command: $MODE (expected pull, push, or sync)" >&2; exit 1 ;;
esac

if [ -n "$PREFER" ] && [ "$PREFER" != "passage" ] && [ "$PREFER" != "pass-cli" ]; then
  echo "--prefer must be 'passage' or 'pass-cli'" >&2
  exit 1
fi

for bin in jq pass-cli passage; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "required command not found: $bin" >&2
    exit 1
  fi
done

# Emits the single pass-cli custom item's field list, one "name<TAB>base64(value)"
# record per line. base64-encoding the value keeps each record on one line even
# if the value itself contains newlines or tabs.
fetch_pass_cli_fields() {
  local json
  if ! json=$(pass-cli item view --vault-name "$VAULT" --item-title "$ITEM" --output json 2>&1); then
    echo "failed to fetch item from pass-cli (vault=${VAULT}, item=${ITEM}). Check pass-cli login:" >&2
    echo "$json" >&2
    exit 1
  fi
  printf '%s' "$json" | jq -r '
    .item.content.content.Custom.sections[]?.section_fields[]?
    | [.name, ((.content.Hidden // .content.Text // "") | @base64)]
    | @tsv
  '
}

passage_show() {
  passage show "$1" 2>/dev/null
}

passage_write() {
  printf '%s' "$2" | passage insert --echo --force "$1" >/dev/null 2>&1
}

pass_cli_write_field() {
  pass-cli item update --vault-name "$VAULT" --item-title "$ITEM" --field "$1=$2" >/dev/null
}

cmd_pull() {
  local name value_b64 value current
  while IFS=$'\t' read -r name value_b64; do
    [ -z "$name" ] && continue
    value=$(printf '%s' "$value_b64" | base64 -d)
    current=$(passage_show "$name" || true)
    if [ "$current" = "$value" ]; then
      continue
    fi
    if [ "$DRY_RUN" = 1 ]; then
      echo "[dry-run] pull: $name (pass-cli -> passage)"
      continue
    fi
    passage_write "$name" "$value"
    echo "pull: $name updated"
  done < <(fetch_pass_cli_fields)
}

cmd_push() {
  local name value_b64 value current
  while IFS=$'\t' read -r name value_b64; do
    [ -z "$name" ] && continue
    value=$(printf '%s' "$value_b64" | base64 -d)
    if ! current=$(passage_show "$name"); then
      echo "push: skip $name (not found in passage)" >&2
      continue
    fi
    if [ "$current" = "$value" ]; then
      continue
    fi
    if [ "$DRY_RUN" = 1 ]; then
      echo "[dry-run] push: $name (passage -> pass-cli)"
      continue
    fi
    pass_cli_write_field "$name" "$current"
    echo "push: $name updated"
  done < <(fetch_pass_cli_fields)

  local path value
  for path in "${ADD_PATHS[@]:-}"; do
    [ -z "$path" ] && continue
    if ! value=$(passage_show "$path"); then
      echo "push --add: $path not found in passage" >&2
      exit 1
    fi
    if [ "$DRY_RUN" = 1 ]; then
      echo "[dry-run] push --add: $path (new field)"
      continue
    fi
    pass_cli_write_field "$path" "$value"
    echo "push --add: $path registered as a new pass-cli field"
  done
}

cmd_sync() {
  local name value_b64 pc_value pg_value conflicts=0
  while IFS=$'\t' read -r name value_b64; do
    [ -z "$name" ] && continue
    pc_value=$(printf '%s' "$value_b64" | base64 -d)
    if ! pg_value=$(passage_show "$name"); then
      if [ "$DRY_RUN" = 1 ]; then
        echo "[dry-run] sync: $name (pull, missing in passage)"
        continue
      fi
      passage_write "$name" "$pc_value"
      echo "sync: $name pulled (was missing in passage)"
      continue
    fi

    if [ "$pg_value" = "$pc_value" ]; then
      continue
    fi

    case "$PREFER" in
      passage)
        if [ "$DRY_RUN" = 1 ]; then
          echo "[dry-run] sync: $name (push, --prefer=passage)"
          continue
        fi
        pass_cli_write_field "$name" "$pg_value"
        echo "sync: $name pushed (--prefer=passage)"
        ;;
      pass-cli)
        if [ "$DRY_RUN" = 1 ]; then
          echo "[dry-run] sync: $name (pull, --prefer=pass-cli)"
          continue
        fi
        passage_write "$name" "$pc_value"
        echo "sync: $name pulled (--prefer=pass-cli)"
        ;;
      *)
        echo "CONFLICT: $name differs between passage and pass-cli (left untouched). Resolve with --prefer passage|pass-cli, or push/pull it individually" >&2
        conflicts=1
        ;;
    esac
  done < <(fetch_pass_cli_fields)

  if [ "$conflicts" = 1 ]; then
    echo "sync: unresolved conflicts remain" >&2
    exit 1
  fi
}

case "$MODE" in
  pull) cmd_pull ;;
  push) cmd_push ;;
  sync) cmd_sync ;;
esac
