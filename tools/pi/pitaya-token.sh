# Prints a bearer token for the homelab inference endpoint, for pi's
# `apiKey: "!command"`.
#
# pi runs the command on every request and caches nothing, and wants the bare
# token rather than the OAuth reply hermes' key_cmd takes. So the reply is
# cached here until a minute before `expires_in`, which keeps passage's age
# forks and the token endpoint out of every turn.

cache="${XDG_CACHE_HOME:-$HOME/.cache}/pi/pitaya-token.json"
now=$(date +%s)

if [ -f "$cache" ]; then
  if jq -e --argjson now "$now" '.expires_at > $now + 60' "$cache" >/dev/null 2>&1; then
    jq -r .access_token "$cache"
    exit 0
  fi
fi

client_id=$(passage show "$PI_PITAYA_PASSAGE_PREFIX/client-id")
client_secret=$(passage show "$PI_PITAYA_PASSAGE_PREFIX/client-secret")

# scope=openid and nothing more, as in tools/hermes/pitaya-token.sh.
reply=$(curl --silent --show-error --fail \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=$client_id" \
  --data-urlencode "client_secret=$client_secret" \
  --data-urlencode "scope=openid" \
  "$PI_PITAYA_TOKEN_URL")

mkdir -p "$(dirname "$cache")"
(umask 077 && jq --argjson now "$now" '{access_token, expires_at: ($now + .expires_in)}' \
  <<<"$reply" > "$cache")
jq -r .access_token <<<"$reply"
