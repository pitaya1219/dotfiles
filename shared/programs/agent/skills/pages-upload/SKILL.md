---
name: pages-upload
description: Upload a local HTML page (and its sibling assets) to pages.pitaya.f5.si so it can be opened and viewed as-is
user-invocable: true
version: 1.0.0
---

Upload one or more local files to `pages.pitaya.f5.si` and get back the URL(s)
they render at.

**This is for content meant to be opened and viewed as-is** — an HTML page,
and the images/CSS/JS it references. It is not a general file store: anything
else (transcripts, documents, arbitrary downloads) already has a home via
`logseq-write`'s `--asset` flag or `session-save`'s transcript attachment,
both of which go to Nextcloud. Use this skill only when the deliverable is
something a browser should render directly.

All auth (ZITADEL client_credentials, token caching) and the upload mechanics
(directory creation, retry-after-mkdir) are handled by the bundled
`pages_upload.py` — do not hand-write curl for this. Credentials come from
`passage`, resolved fresh each run.

## Step 1: Resolve the destination directory

Default to a directory scoped to the current session, so repeated uploads
within one session land together and don't collide with other sessions:

```bash
source "$HOME/.agent/skills/session-save/detect-session.sh"
# Sets SESSION_ID (may be empty if undetected — see fallback below)
DEST_DIR="session-${SESSION_ID:-$(date +%s)}"
```

Reuse this same `detect-session.sh` adapter `session-save` uses rather than
re-deriving the session id — see `Skill(session-save)` for what it resolves
across agent types.

**Override the default when the content is a standing reference the user
will bookmark and expect to find again**, not a one-off session artifact —
e.g. the user says "make this a fixed page" or asks to update something
uploaded in an earlier session. In that case use a short, topic-specific
slug instead (e.g. `--dir homelab` for an infra reference page), and reuse
the exact same slug on later updates so the URL never changes. Ask the user
for the slug if it isn't obvious from context; don't guess at something
meant to be permanent.

## Step 2: Upload

```bash
python3 "$HOME/.agent/skills/pages-upload/pages_upload.py" <path> [<path> ...] \
  --dir "$DEST_DIR"
```

- Pass every sibling asset the HTML references (images, `.css`, `.js`) in the
  same call so they land in the same directory as relative links expect.
- `--name <name>` overrides the uploaded filename; only valid with a single
  path. Omit it to keep each file's own basename.
- On success, prints one `https://pages.pitaya.f5.si/...` URL per file to
  stdout, one per line, and exits 0. Hand the printed URL(s) back to the
  user — don't reconstruct the URL yourself from `$DEST_DIR`, since dufs
  serves a directory containing `index.html` as that page directly (no
  `/index.html` suffix needed in the link you give the user).
- On any failure it exits 1 with the reason on stderr (e.g. an expired or
  revoked `pages-writer` credential, or a network issue reaching
  `auth.pitaya.f5.si` / `pages.pitaya.f5.si`) — surface that message rather
  than retrying blindly.

## Viewing

The uploaded content sits behind Pomerium, gated to whoever holds the
`pages-writer` ZITADEL role (see `core/identity/tofu/grants.tf` in the
homelab repo for the current holders) — a browser hitting the URL for the
first time gets redirected to `auth.pitaya.f5.si` to log in, same as any
other Pomerium-gated homelab host. There is no separate viewer-side secret
to hand out; whoever has `pages-writer` can already reach it.
