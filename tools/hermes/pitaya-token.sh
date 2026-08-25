# Mints a bearer token for the homelab inference endpoint and prints the token
# endpoint's reply unchanged.
#
# The reply is an OAuth 2.0 token response, which is one of the two shapes
# hermes' `key_cmd` accepts (the other being a bare token). Passing it through
# untouched is what lets hermes read `expires_in` and re-mint on its own — a
# bare token would leave it guessing, and these are short-lived.

client_id=$(passage show "$HERMES_PITAYA_PASSAGE_PREFIX/id")
client_secret=$(passage show "$HERMES_PITAYA_PASSAGE_PREFIX/secret")

# scope=openid and nothing more: the endpoint's JWT is validated by the llm
# proxy against the same issuer's JWKS, which needs no audience or resource
# scope. shellm's client (shared/programs/bash/shellm.sh) asks for exactly this
# against the same issuer.
curl --silent --show-error --fail \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=$client_id" \
  --data-urlencode "client_secret=$client_secret" \
  --data-urlencode "scope=openid" \
  "$HERMES_PITAYA_TOKEN_URL"
