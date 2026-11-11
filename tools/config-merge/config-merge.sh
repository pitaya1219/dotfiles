# Usage: config-merge <toml|json|yaml> <generated> <target> [<state>]
#
# Three-way merge of a Nix-generated config into a file the application also
# writes to. <state> holds the previous generation: keys it has that the new
# one lacks were dropped from Nix and are removed from <target>; keys in the
# new generation overwrite; every other key was added by the application and
# is left alone. Arrays and scalars are leaves, so an array is replaced whole.
#
# Without <state> it is a two-way merge: nothing is ever removed, so a key
# dropped from Nix stays in <target> until it is deleted by hand.
#
# The first run has no <state>, so nothing can be recognised as dropped yet.
# <target> is rewritten from scratch each time: comments and key order do not
# survive.

format=$1
generated=$2
target=$3
state=${4:-}

# The documents go to jq as files, not --argjson: one argument is capped at
# 128 KiB on Linux (MAX_ARG_STRLEN), and ~/.claude.json grows past that.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

yq -p "$format" -o json . "$generated" > "$work/new.json"
echo '{}' > "$work/old.json"
[ -n "$state" ] && [ -f "$state" ] && yq -p "$format" -o json . "$state" > "$work/old.json"
echo '{}' > "$work/cur.json"
if [ -f "$target" ] && [ ! -L "$target" ]; then
  yq -p "$format" -o json . "$target" > "$work/cur.json"
fi

merged=$(jq -n \
  --slurpfile cur "$work/cur.json" --slurpfile old "$work/old.json" \
  --slurpfile new "$work/new.json" '
  def leaves: to_entries[] | .key as $k
    | if (.value | type) == "object"
      then (.value | leaves) as $p | [$k] + $p
      else [$k] end;
  $cur[0] as $cur | $old[0] as $old | $new[0] as $new
  | ([$new | leaves]) as $kept
  | [$old | leaves | select(. as $p | $kept | index([$p]) | not)] as $gone
  | ($cur | delpaths($gone)) * $new')

mkdir -p "$(dirname "$target")"
tmp=$(mktemp "$target.XXXXXX")
printf '%s\n' "$merged" | yq -p json -o "$format" . > "$tmp"
chmod 644 "$tmp"
rm -f "$target"
mv "$tmp" "$target"
if [ -n "$state" ]; then
  mkdir -p "$(dirname "$state")"
  rm -f "$state"
  cp --no-preserve=mode "$generated" "$state"
fi
