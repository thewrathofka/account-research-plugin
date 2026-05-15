---
name: arr-writeback
description: Final step of /arr. Computes Research Confidence / Status from the 10 module outputs, performs a single notion-update-page with all agent-owned properties (including empty multi-selects so stale tags clear), creates the page-body block tree via notion-create-pages (canonical order, per-section citation renumbering via arr-page-assembly), and optionally adds a Needs Attention tag + descriptive comment when high-signal fields changed. Supports --dry-run.
allowed-tools: WebFetch, mcp__claude_ai_Notion__notion-fetch, mcp__claude_ai_Notion__notion-update-page, mcp__claude_ai_Notion__notion-create-pages, mcp__claude_ai_Notion__notion-create-comment
---

# arr-writeback — Assemble + Write to Notion

## Purpose

Single chokepoint for all Notion writes in `/arr`. Takes the 10 module outputs and:

1. Computes `Research Confidence` and `Research Status`.
2. Calls `notion-update-page` ONCE with every agent-owned property (including empty multi-selects so stale tags clear).
3. Calls `notion-create-pages` with the page-body block tree from `arr-page-assembly`.
4. Optionally appends a `Needs Attention` tag and a single `notion-create-comment` summarising changes when high-signal fields changed vs the existing page.
5. Honours `--dry-run` — returns the planned payload, performs no Notion writes.

## Inputs

The orchestrator passes:
- `notion_page_id` — the target page
- `module_outputs` — dict keyed by `module_01_gate` … `module_14_hiring_signal`
- `dry_run` — boolean
- `label` — optional run label (used in the change comment)

## Workflow

### 1. Gate short-circuit

If `module_01_gate.gate_result == "fail"`:

- `notion-update-page` with `Research Status="out_of_scope"`, `Research Confidence="high"`, `Last Researched=today`, AND every other agent-owned property cleared (empty multi-select for `Buying Signals`, `Pain Point Tags`, empty text for `Structure Notes`, `sister/child`, `Parent`).
- Append a single paragraph block via `notion-create-pages`: `module_01_gate.note_paragraph`.
- Skip section assembly. Return.

### 2. Compute confidence / status

Aggregate per-module confidences:

| Aggregated outcome | Logic |
|---|---|
| `Research Confidence=high` | every contributing module reported `confidence="high"` or was correctly skipped |
| `Research Confidence=medium` | one or more modules reported `medium`, none `low`, no errors |
| `Research Confidence=low` | any module reported `confidence="low"` |
| `Research Confidence=failed` | any module returned an error/`null` payload that wasn't a graceful skip |

Status mapping:

| Status | When |
|---|---|
| `out_of_scope` | gate fail (handled in step 1) |
| `failed` | confidence=failed |
| `needs_review` | confidence=low |
| `done` | confidence=high or medium |

### 3. Fetch current page (for event detection)

Use `notion-fetch` on `notion_page_id` to read existing properties (we need the prior `Structure Notes`, `Buying Signals`, `Parent`, `sister/child`, `Pain Point Tags`, plus `Needs Attention` so we append rather than overwrite).

### 4. Build the property payload

Single `notion-update-page` call. Always include EVERY agent-owned property — missing keys silently leave stale tags on the record.

| Notion property | Source | Notes |
|---|---|---|
| `Size` | module 1 `employee_count_estimate` → bucket | `<1000` / `1000-2000` / `2000-5000` / `5000+` (deterministic from integer) |
| `Buying Signals` | union(module 7 `triggers_detected`, module 13 `industry_movement_detected → ["industry movement"]`, module 14 `headcount_signal`) | always emit, empty `multi_select=[]` to clear stale tags |
| `Pain Point Tags` | module 4 `tags` | always emit; empty list valid |
| `Structure Notes` | module 6 `structure_note` | empty string if null |
| `sister/child` | module 5 `notable_sister_or_child_brands` joined `", "` | empty string if list empty |
| `Parent` | module 5 `parent_company` (with the self-name rule already applied by module 5) | empty string if `structure_type=standalone` and `parent_company=null` |
| `Last Researched` | today (ISO date) | always |
| `Research Confidence` | step 2 | always |
| `Research Status` | step 2 | always |
| `Needs Attention` | append (step 6) | omit if no event fired |

**DO NOT** write `Buying Intent`, `Prospecting Status`, `Lead Signal`, `New Hire`, `Company Structure`, `Notes`, `Rep`, `Priority Type`, `Account Name`, `Temperature`, `Last Touch Point`, `Strategy`, `Cluster`, `Uncovered`, `Focused`, `Last Hygiene Check`, `Attention Acknowledged At`, `Unify Last Signal`. These are manual / BDR-managed / out of scope.

**Specifically forbidden — `Prospecting Status`:** valid values for that field are `Prospecting` / `SQL` / `SAL` / `Qualified` / `Neglected`. They are BDR conversation-state values, NOT research outputs. Even if a company "looks qualified" from research, NEVER set `Prospecting Status`. This caused CRM hygiene issues in earlier batches (Foodhub, TeamHealth, Tide, Perrigo all had agent-written `Prospecting Status=Qualified` despite Research Status correctly set to `done`).

**Specifically forbidden — `Research Status` values from Prospecting Status vocab:** if you find yourself about to write `Research Status=Qualified` (or `Prospecting`/`SQL`/`SAL`/`Neglected`), STOP. Those belong to `Prospecting Status` (which you don't touch anyway). The only valid `Research Status` values are: `pending`, `done`, `needs_review`, `failed`, `out_of_scope`.

### 5. Build page-body blocks via `arr-page-assembly`

Invoke `arr-page-assembly` with all 10 module outputs. It returns:

- `blocks` — ordered Notion block payloads in canonical order: Overview → Headcount → Possible Pain Points → News → Creative Posture → Ads Running → Competitor Landscape, with per-section citation renumbering and `[N]` markers rewritten as inline `rich_text` link spans.
- `properties_hints` — convenience surface for property alignment.

**Wipe existing page-body children before appending.** Use `notion-fetch` to list existing block IDs and (when supported) delete them, then `notion-create-pages` with the new block list. For the personal Claude Code track, if block deletion isn't available, the orchestrator may instead create child pages or rely on Notion MCP's `notion-create-pages` semantics — match whatever the MCP exposes. Either way: never *append* alongside stale blocks from a previous run.

### 6. Event detection → `Needs Attention` + comment

Diff current page (from step 3) vs new payload. High-signal events that justify a `Needs Attention` tag and a comment:

| Event | Trigger |
|---|---|
| `structure-event-new` | `Structure Notes` changed to a non-null value |
| `structure-type-change` | module 5 `structure_type` differs from a derived view of the prior `Parent` / `sister/child` text |
| `funding-round-new` | `funding round` newly present in `Buying Signals` |
| `agency-switch-new` | `agency switch` newly present |
| `rebrand-campaign-new` | `rebrand/campaign` newly present |
| `ai-initiative-new` | `AI initiative` newly present |
| `tier1-role-open` | module 14 `important_roles_open` contains a `tier_1_marketing_ai` not seen before (best-effort; without snapshot ledger this fires whenever a Tier-1 is present) |
| `layoff-new` | `downsizing` newly present in `Buying Signals` |
| `pain-tag-shift` | module 4 `tags` set differs materially from prior `Pain Point Tags` |

For each event that fires, append its label to `Needs Attention` multi-select (deduplicate against existing tags — append-only; humans clear them).

Emit ONE `notion-create-comment` per run summarising the events that fired. Skip the comment entirely if no event fired. Comment body shape:

```
Run {label or today's date}: detected {n} change(s) since last research.
- {event label}: {one-line context}
- ...
```

### 7. Per-account summary line

Return to the orchestrator a one-line status string:

```
<account>: status=<status> conf=<confidence> (wrote|dry-run, no Notion write)
```

The orchestrator will immediately invoke `arr-format-verifier` on the
written page to confirm the writes landed correctly. arr-writeback does
NOT need to self-verify — verification is the verifier's job.

If, despite this skill's contract, `update_properties` actually skipped
some properties (the failure mode that broke Trane/N26/Related
Companies/YASH in the May 2026 batch), `arr-format-verifier` will catch
it and the orchestrator will re-dispatch. arr-writeback's responsibility
ends at issuing the writes and returning the summary line.

## Dry-run behaviour

Under `dry_run=true`:

- DO NOT call `notion-update-page`, `notion-create-pages`, or `notion-create-comment`.
- DO call `notion-fetch` to compute the diff (read-only).
- Return the full planned payload as the final message so a human can review:
  ```
  {
    "properties": { ... },
    "blocks": [ ... ],
    "needs_attention_appends": [...],
    "comment_body": "..." | null
  }
  ```

## Hard rules

- ONE `notion-update-page` per account. Never split property writes across two calls.
- ALWAYS include every agent-owned property in the update, even when empty — that's how stale multi-select tags clear.
- NEVER write `Buying Intent` — manual-only since 2026-05-11.
- NEVER write `Prospecting Status` — BDR-managed conversation state. (Foodhub/TeamHealth/Tide/Perrigo failure case.)
- NEVER write a Prospecting-Status-shaped value (`Qualified`/`Prospecting`/`SQL`/`SAL`/`Neglected`) to `Research Status`. Research Status is `pending`/`done`/`needs_review`/`failed`/`out_of_scope` only.
- NEVER write to a property the agent does not own (`Lead Signal`, `New Hire`, `Company Structure`, `Notes`, `Rep`, `Priority Type`, `Account Name`, `Temperature`, etc.).
- ALWAYS write `date:Last Researched:start` and `Research Confidence` in the same update_properties call as the rest — these three fields together are what `arr-format-verifier` checks first. Missing any of them = verifier fail = re-dispatch.
- Properties and blocks come from module outputs — this skill does not invent values.
- Citations are renumbered per section by `arr-page-assembly`; do not renumber globally across the whole page.

## Notion property vocabularies (closed sets)

`Buying Signals` (agent-only): `funding round`, `active creative jobs`, `rebrand/campaign`, `agency switch`, `AI initiative`, `industry movement`, `hiring`, `downsizing`.

`Pain Point Tags` (agent-only): `creative production`, `localization`, `new territory`, `strategy`, `audience education`, `competitive displacement`, `brand evolution`, `launch surge`, `AI receptivity`, `post-layoff overflow`.

`Research Status`: `pending` / `done` / `needs_review` / `failed` / `out_of_scope`.

`Research Confidence`: `high` / `medium` / `low` / `failed`.

`Size`: `<1000` / `1000-2000` / `2000-5000` / `5000+`.

## Size-bucket logic (deterministic from integer)

```
<1000        if employee_count_estimate < 1000
1000-2000    if 1000 <= n < 2000
2000-5000    if 2000 <= n < 5000
5000+        if n >= 5000
```

If `employee_count_estimate is null`, omit the `Size` write entirely (don't downgrade an existing value to a wrong bucket).

## Worked example — happy path (Stripe, dry-run)

Planned payload:

```json
{
  "properties": {
    "Size": {"select": {"name": "5000+"}},
    "Buying Signals": {"multi_select": [{"name": "funding round"}, {"name": "AI initiative"}]},
    "Pain Point Tags": {"multi_select": [{"name": "creative production"}, {"name": "AI receptivity"}]},
    "Structure Notes": {"rich_text": [{"type": "text", "text": {"content": ""}}]},
    "sister/child": {"rich_text": [{"type": "text", "text": {"content": ""}}]},
    "Parent": {"rich_text": [{"type": "text", "text": {"content": ""}}]},
    "Last Researched": {"date": {"start": "2026-05-13"}},
    "Research Confidence": {"select": {"name": "high"}},
    "Research Status": {"select": {"name": "done"}}
  },
  "blocks": ["...from arr-page-assembly..."],
  "needs_attention_appends": ["funding-round-new"],
  "comment_body": "Run dry-2026-05-13: detected 1 change(s) since last research.\n- funding-round-new: Stripe raised $50M Series C on 2026-03-12."
}
```

Under `dry_run=true` the skill prints this and exits without calling Notion.
