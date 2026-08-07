"""
Secret Guard Patterns

Regex patterns for detecting secrets in tool output, plus a heuristic
generic KEY=VALUE / "key": "value" matcher for anything named like a secret.
"""

import re


# (name, compiled regex) — matched spans get replaced with [REDACTED:name].
# Ordered roughly by specificity; generic patterns come last so more specific
# names win when spans overlap (scanner keeps first match per span start).
SECRET_PATTERNS = [
    ("private_key", re.compile(
        r"-----BEGIN[ A-Z]*PRIVATE KEY-----[\s\S]+?-----END[ A-Z]*PRIVATE KEY-----"
    )),
    ("aws_access_key_id", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("github_token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,255}\b")),
    ("gitlab_token", re.compile(r"\bglpat-[A-Za-z0-9\-_]{20,}\b")),
    ("slack_token", re.compile(r"\bxox[baprs]-[A-Za-z0-9\-]{10,}\b")),
    ("slack_webhook", re.compile(r"https://hooks\.slack\.com/services/[A-Za-z0-9/]+")),
    ("google_api_key", re.compile(r"\bAIza[0-9A-Za-z\-_]{35}\b")),
    ("stripe_key", re.compile(r"\b[sp]k_live_[0-9a-zA-Z]{24,}\b")),
    ("openai_key", re.compile(r"\bsk-[A-Za-z0-9]{20,}\b")),
    ("anthropic_key", re.compile(r"\bsk-ant-[A-Za-z0-9\-]{20,}\b")),
    ("jwt", re.compile(r"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b")),
    ("bearer_token", re.compile(r"\bBearer\s+[A-Za-z0-9\-_.=]{16,}\b")),
]

# Env-style / JSON-style assignments whose *key name* looks secret-shaped.
# Value is only flagged if it doesn't look like an obvious placeholder —
# see scanner.is_placeholder_value for the exclusion list.
_GENERIC_KEY_NAME = (
    r"\b[A-Z0-9_]*"
    r"(?:secret|token|password|passwd|api[_-]?key|access[_-]?key|private[_-]?key|client[_-]?secret)"
    r"[A-Z0-9_]*"
)
GENERIC_ASSIGNMENT = re.compile(
    r"(?P<key>%s)\s*[:=]\s*['\"]?(?P<value>[^\s'\";,]{8,})['\"]?"
    % _GENERIC_KEY_NAME,
    re.IGNORECASE,
)

PLACEHOLDER_VALUES = {
    "changeme", "change_me", "your-key-here", "your_key_here", "xxx", "xxxx",
    "redacted", "example", "test", "dummy", "placeholder", "todo", "fixme",
    "none", "null", "undefined", "<redacted>", "***", "secret", "password",
}

# Bash command shapes that are highly likely to dump secrets to stdout.
# Deliberately conservative — extend as new leak vectors are found rather
# than trying to be exhaustive up front.
RISKY_COMMAND_PATTERNS = [
    ("env_dump", re.compile(r"(?:^|[;&|]\s*)(env|printenv)\b")),
    ("shell_var_dump", re.compile(r"(?:^|[;&|]\s*)(set|export\s+-p|declare\s+-p)\b")),
    ("dotenv_read", re.compile(
        r"\b(cat|less|more|head|tail|bat)\b[^|;&]*\.env\b(?!\.(example|sample|template|dist))"
    )),
    ("aws_creds_read", re.compile(r"\b(cat|less|more|head|tail|bat)\b[^|;&]*\.aws/credentials\b")),
    ("ssh_key_read", re.compile(r"\b(cat|less|more|head|tail|bat)\b[^|;&]*\.ssh/id_(rsa|ed25519|ecdsa|dsa)\b")),
    ("gpg_export_secret", re.compile(r"\bgpg\b[^|;&]*--export-secret-keys?\b")),
    ("terraform_output", re.compile(r"\bterraform\b[^|;&]*\boutput\b")),
    ("shell_history", re.compile(r"(?:^|[;&|]\s*)history\b")),
]
