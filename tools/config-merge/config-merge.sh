# Usage: config-merge <toml|json|yaml> <generated> <target> <state>
#
# Three-way merge of a Nix-generated config into a file the application also
# writes to. <state> holds the previous generation: keys it has that the new
# one lacks were dropped from Nix and are removed from <target>; keys in the
# new generation overwrite; every other key was added by the application and
# is left alone. Arrays and scalars are leaves, so an array is replaced whole.
#
# The first run has no <state>, so nothing can be recognised as dropped yet.
# <target> is rewritten from scratch each time: comments and key order do not
# survive.

format=$1
generated=$2
target=$3
state=$4

new=$(yq -p "$format" -o json . "$generated")
old='{}'
[ -f "$state" ] && old=$(yq -p "$format" -o json . "$state")
cur='{}'
if [ -f "$target" ] && [ ! -L "$target" ]; then
  cur=$(yq -p "$format" -o json . "$target")
fi

merged=$(jq -n \
  --argjson cur "$cur" --argjson old "$old" --argjson new "$new" '
  def leaves: to_entries[] | .key as $k
    | if (.value | type) == "object"
      then (.value | leaves) as $p | [$k] + $p
      else [$k] end;
  ([$new | leaves]) as $kept
  | [$old | leaves | select(. as $p | $kept | index([$p]) | not)] as $gone
  | ($cur | delpaths($gone)) * $new')

mkdir -p "$(dirname "$target")" "$(dirname "$state")"
tmp=$(mktemp "$target.XXXXXX")
printf '%s\n' "$merged" | yq -p json -o "$format" . > "$tmp"
chmod 644 "$tmp"
rm -f "$target"
mv "$tmp" "$target"
rm -f "$state"
cp --no-preserve=mode "$generated" "$state"
