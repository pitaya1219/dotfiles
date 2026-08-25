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

A comment has to earn its place by helping whoever operates or maintains the
code later. Explanations aimed at the reader of the change itself — what was
added, what it replaced, why this approach was chosen over another — are not
that, however accurate they are. They belong in the commit message and the pull
request body; left in the source they become narration that outlives its context
and eventually misleads.

Comment what the code cannot show and a maintainer would need: the fields a
schemaless record is expected to hold, the upstream cause of a workaround and
the condition for removing it, a constraint that forced an otherwise puzzling
shape.

Before keeping a comment, ask what a maintainer loses if it is gone. If nothing,
delete it.

## Language

Reason in English; respond in Japanese. Code, comments, commit messages,
and PR descriptions stay in English. Never output Chinese — if a Chinese
character slips in, switch back to English or Japanese immediately.

## Git commits

- Never mention AI assistance: no `Co-Authored-By` line naming an AI tool or its
  vendor, and no reference to the agent anywhere in the message.
- Conventional Commits, formatted `prefix: Description ending with period.`
- Prefixes: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`, `test:`, `style:`

## Terminal tabs

When the session runs inside herdr — `HERDR_ENV` is set — name the tab after
the task as soon as you know what it is:

```
herdr-tab-name 'logseq read skill'
```

The tab starts out labelled with the git branch, which says where you are but
not what you are working on. Replace it once, and again if the task turns into
something else. Keep it to about 12 columns: the tab bar divides its width
among every tab in the workspace, and Japanese costs two columns per character.

Outside herdr the command exits without doing anything.
