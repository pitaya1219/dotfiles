---
name: my-review
description: Perform code review in pitaya1219's personal review style
user-invocable: true
version: 1.1.0
---

# My Review Skill

## What This Skill Does

Performs a code review using pitaya1219's established review style.
The review is done in four phases: diff analysis, context gathering (when needed), review output, and optional post-processing.

## Usage

```
/my-review              # Review current branch diff vs base branch
/my-review --pr <N>     # Review a specific PR by number
/my-review --fix        # Apply auto-fixable suggestions to files after review
/my-review --comment    # Post findings as inline PR comments
```

## Phase 1: Get the Diff

Obtain the diff to review.

**Default (no `--pr`):** compare the current branch against the base branch.

```bash
BASE=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
BASE=${BASE:-main}
git diff origin/$BASE...HEAD
```

**With `--pr <N>`:** obtain the diff for the specified PR. Check the remote URL (`git remote get-url origin`) to determine the platform and use the most appropriate available method (CLI tool, MCP tool, git fetch, etc.) to retrieve the PR diff.

Read and understand all changed files before proceeding.

## Phase 2: Context Gathering

After reading the diff, identify specific areas where business context or external specifications are needed to perform an accurate review. Do **not** ask generic questions — only ask what cannot be inferred from the code itself.

**Ask questions when you encounter:**
- Logic tied to external system behavior (API specs, DB schema constraints, event sequences)
- Business rules about when errors should be raised vs. silently skipped
- Requirements that dictate which fields should be active vs. inactive records
- Uncertainty about whether a code path corresponds to a specific business case (e.g., "termination" vs. "contract change")
- Tickets or specs referenced in comments but not visible in the diff

**Do NOT ask about:**
- Things readable from the code or its context
- General coding conventions (apply the review perspectives directly)
- Implementation details already visible in the diff

Collect all questions and present them **in a single batch** to the user. If no context is needed, or if the user responds that no additional context is necessary, skip to Phase 3 immediately.

Example question batch format:
```
レビューにあたって確認させてください:

1. [L.42 suspension_use_date] 中止のケースと契約変更のケースで取得元が異なりますか?
2. [L.87 external_4x_number] 存在しない場合はエラーにすべきですか、それともスキップ扱いですか?
3. 関連するチケットや仕様書があれば共有してください。
```

Wait for the user's response before proceeding to Phase 3.

## Phase 3: Review Output

Apply **all** of the following review perspectives to the diff. For each finding, output a comment in the appropriate format.

---

### Review Perspectives

#### 1. 要件・仕様への正確な準拠

- Does the implementation match the requirements from the ticket/spec?
- Are header/footer columns correct? Do field names, counts, and formats match the spec?
- Is the correct record (active vs. inactive) used for each output field?
- Flag discrepancies with a reference to the spec: `チケット/仕様書の再確認をお願いします。`

#### 2. 命名・コメントの適切さ

- Do method and variable names accurately reflect their full behavior (including side effects or conditions)?
  - Bad: `is_active()` when it also checks a record type
  - Good: `is_billing_flag_active()`
- Are comments written as "what it does" not "what we want to do"?
  - Bad: `# ログの確認をしやすくするために、FluentBitのログにもCloudWatchのログストリームのURLを出力するログを出力する`
  - Good: `# FluentBitのログにCloudWatchログストリームのURLを出力する`
- For non-obvious code, recommend `NOTE:` or `TODO:` annotation comments (they get editor highlighting):
  ```
  # NOTE: `valid_to: None` なものはactiveとみなす為、inactiveで`valid_to: None`なデータは現行では存在しない
  ```
- For commented-out code left intentionally, require a comment explaining why it's kept.

#### 3. 型アノテーションの厳密さ

- Are generic container types specified? (`set` → `set[int]`, `list` → `list[str]`)
- Is `==` used for value comparison instead of `is` for non-singleton types?
  - `is None` / `is not None` → correct
  - `result is "string"` → incorrect, use `result == "string"`
- Does the return type hint match the actual return behavior (e.g., `X | None` when the function can raise instead of returning `None`)?

#### 4. テストの品質・網羅性

- Do test parameter names describe the test scenario from the caller's perspective, not the internal implementation?
  - Bad: `id="expired"` (internal concept)
  - Good: `id="Active campaign found"`, `id="Has a non-matching type and an active matching type"`
- Are edge cases covered? (NULL/None values, both branches of conditional logic, empty collections)
- When both header and footer are generated, are both asserted in the test?
- Are there test cases for each distinct code path introduced by the change?

#### 5. エラーハンドリング（サイレント失敗の撲滅）

- If required data is missing, should the code raise an error or silently skip?
  - Default: raise an error. Silent skip only when explicitly specified in requirements.
- Is there any path where an error is caught but the downstream code still receives invalid/empty data?
- Are errors re-raised with enough context? (include IDs, field values in the error message)
- Flag any case where processing continues with a corrupted or incomplete state.

#### 6. コード設計・責務分離

- Are instance variables (`self.xxx`) used to pass data between methods when function parameters would be clearer?
  - Prefer: `return (result_a, result_b, result_c)` over mutating `self.result_a`, etc.
- Is the placement of logic logical? (e.g., file write operations grouped together, not scattered)
- Are deeply nested `try/except` blocks avoidable?
- Is the same DB/API call made multiple times when it could be cached or consolidated?
- Are magic numbers replaced with named constants or Enums?

#### 7. パフォーマンス・DB設計

- For SQL queries: Is `DISTINCT` needed to prevent duplicate rows?
- Are frequently searched columns indexed?
- Is the transaction scope as narrow as possible to reduce lock contention?
  - Committing inside a loop is often intentional to keep transactions short.
- Could multiple external API calls be consolidated into one?
- For `INSERT`-only operations (no `UPDATE`), a transaction may be unnecessary — flag if added unnecessarily.

#### 8. ビジネスロジックの正確性

- When the diff touches active/inactive record handling, state transitions, or event-type-specific logic: verify the logic is consistent with what was described in the context-gathering phase.
- Flag any assumption that looks fragile (e.g., "this field is always set" or "this will never be None") without defensive handling.
- When business logic branches on event types or states, verify all relevant cases are covered.

#### 9. セキュリティ・データ保護

- Does test or debug code expose PII? (names, phone numbers, IDs, payment references in logs or fixtures)
- Are dev and prod environments properly separated for configuration values?
  - Flag: `この変更、本番環境にも影響があります。開発・本番で分けられるようにして欲しいです。`

---

## Output Format

Use the following notation, matching the reviewer's established style:

### Notation Guide

| Notation | Meaning |
|----------|---------|
| _(no prefix)_ | Must fix — required for approval |
| `[suggestion]` | Recommended — strong preference but optional |
| `[want]` | Nice to have — clearly optional, can be deferred |
| `\[任意]` | Truly optional — minor style preference |

### Code Suggestions

Use suggestion blocks for concrete fixes. **Note: suggestion blocks render as "Apply suggestion" buttons only on GitHub. On Gitea and other platforms, they appear as plain code blocks.**

````
```suggestion
    ) -> tuple[set[int], int, int, int, int]:
```
setの型も明示していただきたいです。Editorの力に頼ってミスを検知しやすくなる為です。
````

### Addressing Specific People

When a comment is directed at a specific reviewer or author, mention their account name:
```
@<相手のアカウント名>
この条件、中止のケースだけでなく契約変更のケースも考慮が必要です。
```

### References

Link to related comments, tickets, or documentation when available:
```
[こちらのコメント](URL) と同様の内容です。
```

---

## Approval / Request Changes Decision

After completing the review:

- **Approve (LGTM)**: No required fixes, only `[suggestion]`/`[want]` items at most
- **Comment**: Required fixes exist but are minor enough to not block — ask for changes before final approval
- **Request Changes**: Required fixes that must be addressed before merge

State the decision clearly at the end:

```
---
処理自体は良さげなので、approveします。
`[want]` としたところは後のリファクタリングタスクなどに回すのも手かと思います。
```

or:

```
---
いくつか要件との差異があるため、Changes Requestedとします。
コメントした内容で不明瞭な点があれば、改めて認識合わせしましょう。
```

After outputting the decision, ask the user whether to post the findings as inline PR comments:

```
このままPRにコメントとして投稿しますか？
```

If the user confirms, proceed to Phase 4 (`--comment` mode). If not, end here.

**`--comment` flag:** skip this confirmation and proceed directly to Phase 4.

---

## Phase 4: Post-Processing (optional flags)

### `--fix`: Apply suggestions to files

After Phase 3, apply suggestion blocks to the actual source files:

1. For each `suggestion` block in the review output, identify the target file and line range from the diff context
2. Apply the change using the Edit tool
3. Output a summary of all applied changes

Only apply suggestions that are unambiguous. Skip and flag any suggestion that requires judgment.

### `--comment`: Post as inline PR comments

Post the findings from Phase 3 as inline review comments on the PR. Check the remote URL (`git remote get-url origin`) to determine the platform, then use the most appropriate available method (CLI tool, MCP tool, API, etc.) to post the comments.

Post each finding as a separate inline comment on the relevant line/hunk. Conclude with an overall review comment summarizing the Approval / Request Changes decision.
