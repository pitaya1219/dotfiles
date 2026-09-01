# code-flow-html — markup and scenario conventions

Details that would bloat `SKILL.md`. Read this while filling `template.html`.

## Markup shape

```
.flow                      #flow — the animated region, nothing else goes in here
└── .stage[data-s="sN"]    one step in time, top to bottom
    ├── .stage-label       short uppercase caption
    └── .row
        └── .node[id="n-…"]  the alternatives available at that step
            ├── .fn        the identifier — function name, condition, log call
            └── .d         one or two lines of what it does (optional)
```

A stage is *when*, a node is *what*. Two things that can happen at the same
point in time belong in the same stage as sibling nodes; two things that happen
one after the other belong in different stages, even if only one node lives in
each.

The connector line between stages is drawn by `.stage::after`, so stages must be
direct children of `.flow`. Nesting a stage inside another breaks the line.

### Node classes

| Class | Meaning | Typical content |
|---|---|---|
| *(none)* | pure computation, no side effect | helper calls, classification, log lines |
| `decision` | a branch point — renders dashed | `foo が真 ?`, `既存の行がある ?` |
| `io` | crosses a process boundary | DB query, HTTP call, queue put |
| `term` | the path ends here, having written nothing | `warn → return` |
| `bad` | the abnormal path | `except → raise`, forced degradation |

`decision` is a shape, not a color, so it combines with the others
(`class="node decision term"` is valid). The four colors are the whole
vocabulary — see the rule in `SKILL.md`.

### ID convention

Node ids must match `n-[a-z-]+`: lowercase, hyphen-separated, `n-` prefix. The
verification one-liner in `SKILL.md` relies on that shape to tell node ids apart
from every other quoted string in the file, so an id like `n_readRow` or
`node-1` will slip past the check unnoticed.

Name after the thing, not the position: `n-latest`, `n-oversized`, `n-w-put`.
Positional names (`n-step3`) go stale the moment a stage is inserted.

## `SCENARIOS`

```js
{
  key:"retrig-same",                  // unique; used as the button's data-k
  label:"再投入 → 同じエラー",           // button text, kept short
  desc:"<b>既存 SK を UpdateItem</b>。…", // HTML allowed
  res:"結果: 既存行を更新 / attempt++",   // one-line outcome, rendered muted
  path:["n-except","n-call", …],       // node ids, in traversal order
  stages:["s1","s2","s3","s4"]         // data-s values, in traversal order
}
```

- **`desc`** — lead with the conclusion in `<b>`, then the reason it takes that
  route. This is where a reader looks first, so it carries the argument; the
  nodes only carry the names.
- **`res`** — what the outside world observes afterwards: rows written, calls
  made, nothing at all. Keep it to one line.
- **`path`** — traversal order, which drives the lighting order. Include the
  decision nodes the path evaluates, not just the ones it "chooses": a scenario
  that stops early still passes through the guard that stopped it.
- **`stages`** — only the stages the path actually reaches. A scenario that
  returns at stage 2 lists `["s1","s2"]`; listing `s3`–`s8` would light up
  connector lines for steps that never run.

`path` and `stages` advance on separate clocks (`step` and `step * 1.4`), so the
stage line stays slightly behind the nodes rather than tracking them exactly.
That is intentional — the lag reads as "the step is still in progress". Do not
try to make them line up.

### Choosing which scenarios to include

One per distinct outcome of the decision tree, plus the abnormal paths that are
worth arguing about. The set should cover every terminal node in the markup: a
`term` or `bad` node no scenario reaches is either dead code or a missing
scenario, and both are worth knowing.

Order them from most ordinary to most exceptional. The first button is the one a
reader presses without thinking.

## Static sections

Anything not animated uses the plain vocabulary already in the stylesheet:

- `.svgwrap` + `.sm-*` for hand-drawn SVG — `.sm-box` (with `.open` / `.done` /
  `.hist` fills), `.sm-t` title text, `.sm-s` subtitle, `.sm-e` edge,
  `.sm-el` edge label. The arrowhead marker `#ah` is defined once in the first
  SVG's `<defs>`; later SVGs in the same document reuse it, so keep that first
  SVG or move the `<defs>` block.
- `.tablewrap` + `table` for lookup tables.
- `.box` / `.box.alert` for callouts — open questions, review findings, caveats
  that do not belong to any single node.

All of them inherit the same tokens, so they stay consistent in both themes
without extra work.

## Themes

Colors are defined three times on purpose: bare `:root` (light), then
`@media (prefers-color-scheme: dark)` guarded with `:root:not([data-theme="light"])`,
then `:root[data-theme="dark"]`. The media block follows the system setting; the
attribute blocks let you force either theme for a screenshot or a check.

Add new colors as tokens in all three places. A literal color dropped into a
rule looks fine in whichever theme you happened to be in and wrong in the other.
