# herdr-tab-name — rename the herdr tab this shell is running in.
#
# Called by the coding agent itself once it knows what the session is about, so
# the tab bar reads as a list of tasks rather than a list of branches. What the
# agent replaces is the branch name agent-open put there; leaving it alone is a
# valid outcome, not a failure.
#
# Outside herdr it exits without doing anything, which is what makes it safe to
# name in instructions every agent loads no matter where it runs.
#
# Usage: herdr-tab-name <short task name>

# The tab bar divides its width among every tab in the workspace, so this is a
# guard against one runaway label crowding out the rest — not a style rule. The
# instruction in ~/.agent/conventions.md asks for something well under it.
MAX_COLUMNS="${HERDR_TAB_NAME_MAX_COLUMNS:-20}"

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0

if [ "$#" -eq 0 ]; then
  printf 'herdr-tab-name: needs a name\n' >&2
  exit 1
fi

# One line, single-spaced: a label with a newline in it would push the rest of
# the tab bar around.
label=$(printf '%s' "$*" | tr '\n\t' '  ' | tr -s ' ')
label=${label# }
label=${label% }

# Cut by display column rather than character count. CJK draws two columns per
# character, and bash indexes by character under a UTF-8 locale, so this loop
# counts what the terminal will actually draw. Non-ASCII is assumed
# double-width, which over-counts an accented Latin character by one column —
# a cosmetic loss, not a broken layout.
truncated=""
width=0
for (( i = 0; i < ${#label}; i++ )); do
  char=${label:i:1}
  case $char in
    [$'\x20'-$'\x7e']) char_width=1 ;;
    *) char_width=2 ;;
  esac
  if [ $((width + char_width)) -gt "$MAX_COLUMNS" ]; then
    break
  fi
  truncated="$truncated$char"
  width=$((width + char_width))
done
[ -n "$truncated" ] || exit 0

# HERDR_PANE_ID names the pane, and only the pane; the tab it sits in has to be
# looked up. `pane current` would answer for whichever pane has focus, which is
# not necessarily the one this agent is running in.
tab=$({ herdr pane get "$HERDR_PANE_ID" 2>/dev/null |
  jq -r '.result.pane.tab_id // empty' 2>/dev/null; } || true)
if [ -z "$tab" ]; then
  printf 'herdr-tab-name: no tab found for pane %s\n' "$HERDR_PANE_ID" >&2
  exit 1
fi

out=$(herdr tab rename "$tab" "$truncated" 2>&1) || {
  printf 'herdr-tab-name: rename failed: %s\n' "$out" >&2
  exit 1
}
