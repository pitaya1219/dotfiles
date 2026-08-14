# Conventions

Conventions that hold across every repository and every agent. Anything specific
to one agent or one repository belongs in that agent's or that repository's own
instruction file, not here.

## Comments

Do not comment what the code or the configuration value already states. An
option name paired with its value usually speaks for itself, so leave it bare:
`deletionProtection: true` does not need "to prevent accidental deletion", and
restating a mechanism the reader already knows ("DynamoDB is schemaless, so
non-key attributes need no definition") carries no information.

Comment what the code cannot show: the fields a schemaless record is expected to
hold, the upstream cause of a workaround and the condition for removing it, a
constraint that forced an otherwise puzzling shape.

Reasoning about why a change was made belongs in the pull request body.

## Git commits

- Never mention AI assistance: no `Co-Authored-By` line naming an AI tool or its
  vendor, and no reference to the agent anywhere in the message.
- Conventional Commits, formatted `prefix: Description ending with period.`
- Prefixes: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`, `test:`, `style:`
