"""
Unit tests for secret_guard scanner.

Tests the pure detect/redact/is_risky_command logic with parametrized cases.
"""

import pytest

from secret_guard.scanner import find_secrets, is_risky_command, redact


@pytest.mark.parametrize(
    "text,expected_name",
    [
        ("aws_key = AKIAABCDEFGHIJKLMNOP", "aws_access_key_id"),
        (
            '{"clientId":"123","clientSecret":"oBhbCVuTgxdxdm85zph023VsUHONv4bnmSD2jl3CV43CTcTe0ohht7aUl4N0JkA1"}',
            "generic_secret_assignment",
        ),
        (
            "-----BEGIN RSA PRIVATE KEY-----\nMIIB...\n-----END RSA PRIVATE KEY-----",
            "private_key",
        ),
        ("token: ghp_" + "a" * 36, "github_token"),
        ("token: glpat-" + "a" * 20, "gitlab_token"),
        ("SLACK_TOKEN=xoxb-1234567890-abcdefghij", "slack_token"),
        ("webhook https://hooks.slack.com/services/T00/B00/XXXXXXXXXXXXXXXXXXXXXXXX", "slack_webhook"),
        ("key=AIza" + "a" * 35, "google_api_key"),
        ("stripe: sk_live_" + "a" * 24, "stripe_key"),
        ("OPENAI_API_KEY=sk-" + "a" * 20, "openai_key"),
        ("ANTHROPIC_API_KEY=sk-ant-" + "a" * 20, "anthropic_key"),
        ("Authorization: Bearer " + "a" * 20, "bearer_token"),
        (
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dQw4w9WgXcQ_abcdefghi",
            "jwt",
        ),
    ],
)
def test_detects_known_secret_shapes(text, expected_name):
    matches = find_secrets(text)
    names = [m[0] for m in matches]
    assert expected_name in names


@pytest.mark.parametrize(
    "text",
    [
        'API_KEY=your_key_here',
        'password = "changeme"',
        'client_secret: <redacted>',
        'API_TOKEN=xxx',
        '# password=example',
        'SECRET=""',
    ],
)
def test_placeholder_values_not_flagged(text):
    assert find_secrets(text) == []


def test_generic_assignment_flags_secret_shaped_value():
    matches = find_secrets("DB_PASSWORD=Sup3rSecretValue123")
    assert any(name == "generic_secret_assignment" for name, _, _ in matches)


def test_redact_preserves_surrounding_text():
    text = "before AKIAABCDEFGHIJKLMNOP after"
    redacted, names = redact(text)
    assert names == ["aws_access_key_id"]
    assert redacted == "before [REDACTED:aws_access_key_id] after"
    assert "AKIA" not in redacted


def test_redact_no_secrets_returns_original():
    text = "just a normal log line, nothing sensitive here"
    redacted, names = redact(text)
    assert redacted == text
    assert names == []


def test_redact_handles_multiple_non_overlapping_secrets():
    text = f"aws={'A' * 0}AKIAABCDEFGHIJKLMNOP slack=xoxb-1234567890-abcdefghij"
    redacted, names = redact(text)
    assert set(names) == {"aws_access_key_id", "slack_token"}
    assert "AKIA" not in redacted
    assert "xoxb-" not in redacted


@pytest.mark.parametrize(
    "command",
    [
        "env",
        "printenv",
        "printenv AWS_SECRET_ACCESS_KEY",
        "set",
        "export -p",
        "declare -p",
        "cat .env",
        "cat backend/.env",
        "cat ~/.aws/credentials",
        "cat ~/.ssh/id_rsa",
        "gpg --export-secret-keys",
        "terraform output -json",
        "history",
    ],
)
def test_flags_risky_commands(command):
    assert is_risky_command(command) is not None


@pytest.mark.parametrize(
    "command",
    [
        # Newline-separated statements (a single multi-line Bash call, not
        # joined by ;/&/|) -- the risky statement isn't the first line.
        'echo "checking env"\nprintenv SSH_AUTH_SOCK',
        "echo start\nenv\necho end",
        # Process substitution / command substitution / subshell / backtick
        # -- all start a fresh command right after an opening `(` or `` ` ``.
        "diff <(env | sort) <(ssh host env | sort)",
        "cat <(printenv)",
        "CID=$(env)",
        "(env)",
        "echo `env`",
    ],
)
def test_flags_risky_commands_in_nested_or_multiline_shapes(command):
    assert is_risky_command(command) is not None


@pytest.mark.parametrize(
    "command",
    [
        "ls -la",
        "cat README.md",
        "git status",
        "npm test",
        "cat .env.example",
        "cat .env.sample",
        "docker run --env FOO=bar image",
        "envsubst < template.conf",
    ],
)
def test_allows_benign_commands(command):
    assert is_risky_command(command) is None


@pytest.mark.parametrize(
    "command",
    [
        "tofu output -raw vikunja_client_secret",
        "terraform output -json",
        "passage show shellm/client/secret",
        "passage show homelab/zitadel/apps/gitea/client/secret",
    ],
)
def test_flags_bare_secret_dumps(command):
    assert is_risky_command(command) is not None


@pytest.mark.parametrize(
    "command",
    [
        # Piped straight into another command -- never reaches this tool
        # call's own visible stdout.
        "tofu output -raw x_client_secret | passage insert -m -f homelab/x/client/secret",
        "passage show shellm/client/secret | passage insert -m -f other/path",
        # Captured via $(...) into a variable, not displayed.
        'CID=$(tofu output -raw x_client_id 2>/dev/null)',
        'SECRET=$(passage show homelab/x/client/secret)',
        # Multi-line: captured on one line, safely consumed on a later one
        # -- this is the exact shape used to rotate a Zitadel client's
        # secret in passage without ever displaying it.
        "CID=$(tofu output -raw x_client_id 2>/dev/null)\n"
        "CSECRET=$(tofu output -raw x_client_secret 2>/dev/null)\n"
        'echo -n "$CID" | passage insert -m -f homelab/x/client/id\n'
        'echo -n "$CSECRET" | passage insert -m -f homelab/x/client/secret',
    ],
)
def test_allows_piped_or_captured_secret_dumps(command):
    assert is_risky_command(command) is None
