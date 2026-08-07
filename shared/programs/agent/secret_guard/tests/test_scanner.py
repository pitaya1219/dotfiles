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
        "ls -la",
        "cat README.md",
        "git status",
        "npm test",
        "cat .env.example",
        "cat .env.sample",
    ],
)
def test_allows_benign_commands(command):
    assert is_risky_command(command) is None
