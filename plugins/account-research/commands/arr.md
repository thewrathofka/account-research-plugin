---
description: Run the 11-module account research pipeline against the Notion All Accounts CRM. Orchestrates per-module skills via parallel subagents. On-demand only — no schedule, no cron.
argument-hint: [<account name> | --batch] [--rep NAME] [--priority NAME] [--max N] [--since N] [--dry-run] [--label TAG]
allowed-tools: Agent, Skill, WebSearch, WebFetch, Bash, mcp__claude_ai_Notion__notion-search, mcp__claude_ai_Notion__notion-fetch, mcp__claude_ai_Notion__notion-update-page, mcp__claude_ai_Notion__notion-create-pages, mcp__claude_ai_Notion__notion-create-comment
---

# /arr — Account Research Agent (orchestrator)

Researches B2B accounts in the Notion **All Accounts** CRM and writes
findings back to each account's page. Native Claude Code: orchestrator
command → parallel **subagents** (one per research module) → per-module
**skills** carry the spec → **tools** (WebSearch, WebFetch, Notion MCP)
do the actual work. Runs only on `/arr`.

User-supplied arguments: `$ARGUMENTS`

---

## Step 0 — Parse arguments

Resolve `$ARGUMENTS` into one of:

- **Single account:** first non-flag word = account name (substring match).
  Example: `/arr Stripe` or `/arr "AlphaSense"`.
- **Batch:** `--batch` → all accounts matching the Rep + Priority filter
  whose `Last Researched` is older than `--since` (default 30) days or empty.

Flags: `--dry-run`, `--rep NAME` (default Katarina),
`--priority NAME` (default `Priority A`), `--max N`, `--since N`,
`--label TAG`.

If neither mode is given, ask once which the user wants.

---

## Step 1 — Resolve account list (Notion MCP)

- **All Accounts DB:** `6d510b5a-9c8f-490f-8600-429184341edc`
- **Money Moguls CRM parent page:** `3523435e-7148-8111-b9be-df6e2c5844b9`
- **Canonical batch view (recommended):** "Unresearched Priority B" — a Notion view
  with filter `Rep=<rep> + Priority Type=<priority> + Last Researched is empty`,
  sorted by `Account Name ASC`. The MCP `notion-query-database-view` tool caps
  results at 100 with no cursor passthrough, so a pre-filtered view is the only
  way batch mode reliably surfaces accounts beyond position 100.

For batch mode, prefer `notion-query-database-view` against the canonical view URL.
If no such view exists yet, fall back to `notion-fetch` against the DB ID with
filter on Rep + Priority Type + `Last Researched is empty`, sorted ascending —
still capped at 100, but covers most cases.

Apply `--since` and `--max` caps.

Cache the page IDs in working memory — every module needs them later.

---

## Step 2 — Per-account loop

For each account, run the pipeline below. Don't fan out across accounts
in parallel (Notion's rate limits + the cost of debugging interleaved
output isn't worth it for personal use); fan out **within** an account.

### 2a-pre. Disambiguation (only when needed)

Before any research, check if `account_name` is on the **ambiguous-names watchlist**:

```
Brunswick, CAI, Tide, Centric, Apex, Bridge, Stage, Core,
Material, Material+, Material +, Crew, Stripe (UK vs US payments),
Halo, Atlas, Anchor, Element
```

(Expand this list whenever a new ambiguous name surfaces in a batch run.)

If the account name matches OR the previous run flagged the account as
`needs_review` with duplicate/ambiguity language, invoke the
**`arr-disambiguator`** skill with the account name + any CRM hints
(Industry/Region/Size/Notes). It returns `resolved_entity_name` +
`resolved_entity_short` — pass BOTH into every module subagent below
so they research the right company.

For unambiguous names, **skip this step entirely** — most accounts
don't need disambiguation and the cost isn't justified.

### 2a. Gate (module 1, sequential, blocking)

Invoke the **`arr-module-01-gate`** skill with the account context
(including disambiguation results if any). If it returns `gate=fail`:
- Set `Research Status=out_of_scope` on the account page.
- Append the note paragraph as a child block.
- Skip all remaining modules. Move to the next account.

### 2b. Fan out research (modules 3, 5, 6, 7, 9, 10, 12, 13, 14)

Spawn 9 **subagents in parallel** — a single message with 9 Agent tool
calls. Use `subagent_type=Explore` for read-only research (each subagent
has WebSearch/WebFetch/Skill but not Notion write tools, which is
exactly what we want here — the orchestrator owns all Notion writes).

For each subagent, the prompt is:

> Research **module NN** for account **<NAME>** (Notion page ID
> `<PAGE_ID>`). Load the **`arr-module-NN-<slug>`** skill via the Skill
> tool — it contains the full spec, JSON output schema, citation rules,
> and signal-trigger logic. Run the searches the skill asks for, fill
> in the schema, and return the JSON output as your final message
> (no prose around it). If a search fails, include `confidence=low`
> and a note in the JSON — never invent facts to fill the schema.

The 9 module ↔ skill mappings:

| Module | Skill | What it returns |
|---|---|---|
| 3 | `arr-module-03-revenue` | Overview text + customer/product fields |
| 5 | `arr-module-05-corporate` | `Parent` + `sister/child` values |
| 6 | `arr-module-06-structural-news` | `Structure Notes` phrase (from constrained vocab) |
| 7 | `arr-module-07-triggers` | `Buying Signals` additions + News context |
| 9 | `arr-module-09-creative` | Creative Posture paragraph |
| 10 | `arr-module-10-ads` | Per-platform Ads Running bullets |
| 12 | `arr-module-12-competitors` | Top 3 competitors + differentiation |
| 13 | `arr-module-13-industry` | 2–3 category stories + maybe `industry movement` |
| 14 | `arr-module-14-hiring` | Headcount summary + `hiring`/`downsizing` signal |

Collect all 9 JSON outputs.

### 2c. Synthesis (module 4, sequential, after fan-out)

Invoke the **`arr-module-04-pain-points`** skill with **all 9 module
outputs** as context. It produces the `Possible Pain Points` bullet
section (v3.0.0 layout: intro line + one bullet per pain + tag bullet)
and the `Pain Point Tags` multi-select values.

Module 4 is synthesis, not search — don't spawn a research subagent.
Run it as a Skill call inside the orchestrator.

### 2d. Assemble + write (the `arr-writeback` skill)

Invoke the **`arr-writeback`** skill with: the account page ID, all 10
module outputs (1, 3, 4, 5, 6, 7, 9, 10, 12, 13, 14), the `--label`
flag, and `--dry-run`. The skill handles:

1. Computing `Research Confidence` + `Research Status` from per-module
   confidences and errors.
2. Single `notion-update-page` call — all agent-owned properties,
   including empty multi-selects so stale tags clear.
3. `notion-create-pages` for the page-body section block tree in the
   canonical order (Overview → Headcount → Possible Pain Points → News
   → Creative Posture → Ads Running → Competitor Landscape).
4. Per-section citation renumbering (`[N]` → inline `rich_text` link
   spans).
5. Optional event detection → `Needs Attention` tag + single
   `notion-create-comment` summarising changes (only if a high-signal
   field actually changed vs the existing page state).

Under `--dry-run`, the skill returns the planned write payload but
performs no Notion mutations.

### 2e. Post-write verification (the `arr-format-verifier` skill)

Immediately after `arr-writeback` completes for an account, invoke the
**`arr-format-verifier`** skill with the account's page ID and today's
date. It re-fetches the page and validates:

- All required properties were actually written (catches Failure A —
  body landed but properties skipped).
- Body uses the canonical PMG section structure (catches Failure B —
  `# H1` + custom sections).
- `Prospecting Status` was not touched (catches Failure C — agents
  writing to BDR-managed fields).
- `Buying Signals` / `Pain Point Tags` values are from the closed
  vocabularies.
- `Parent` vs `sister/child` aren't swapped (catches Failure D —
  parent name in the wrong field).

If verifier returns `result=fail`, the orchestrator should:
1. Log the diagnostic to the summary.
2. Optionally re-dispatch the account in **fix-mode** — a targeted
   re-run that re-invokes only the failing modules + `arr-writeback`.
   (For the personal MVP: a single re-dispatch attempt; on second
   fail, leave `Research Status=needs_review` and continue.)

Under `--dry-run`, the verifier still runs (it's read-only) — useful
for previewing what the writeback would look like.

### 2f. Per-account summary line

Print one line per account, in this shape:

```
Stripe: status=done conf=high (wrote, verified)
AlphaSense: status=needs_review conf=low (wrote, verified)
Foo Corp: status=out_of_scope conf=high (wrote — gate failed)
Bar Inc: status=done conf=high (wrote, VERIFIER FAILED: <diagnostic>)
```

Under `--dry-run`, replace `(wrote, verified)` with `(dry-run, no Notion write)`.

---

## Notion schema (contract)

Properties the agent owns (writes every run; missing key = silently
leaves stale tags, so always include them):

| Property | Type | Module | Notes |
|---|---|---|---|
| `Size` | select | 1 | `<1000` / `1000-2000` / `2000-5000` / `5000+` |
| `Buying Signals` | multi-select | 7+13+14 | **agent-only**, overwrite semantics |
| `Pain Point Tags` | multi-select | 4 | agent-only |
| `Structure Notes` | text | 6 | constrained vocabulary, real names only |
| `sister/child` | text | 5 | |
| `Parent` | text | 5 | self-name if parent-with-children |
| `Last Researched` | date | always | today |
| `Research Confidence` | select | always | high/medium/low/failed |
| `Research Status` | select | always | done/needs_review/failed/out_of_scope |
| `Needs Attention` | multi-select | event detection | append-only; human clears |

**Do NOT write `Buying Intent`** — that's manual-only since the
2026-05-11 role swap.

`Buying Signals` vocabulary: `funding round`, `active creative jobs`,
`rebrand/campaign`, `agency switch`, `AI initiative`,
`industry movement`, `hiring`, `downsizing`.

`Pain Point Tags` vocabulary: `creative production`, `localization`,
`new territory`, `strategy`, `audience education`,
`competitive displacement`, `brand evolution`, `launch surge`,
`AI receptivity`, `post-layoff overflow`.

---

## What this plugin deliberately does NOT do

- **No scheduled runs.** No GHA, no cron, no `/schedule` registration.
  Only fires on `/arr`.
- **No cost tracking.** No `--cost-summary`, no SQLite log, no Tavily
  $-per-call accounting. The Python project at
  `~/code/account-research-agent/` is the one that tracks all that.
- **No paid third-party APIs by default.** Tavily / Apify / jobspy /
  Greenhouse ATS are all replaced with `WebSearch` + `WebFetch`. (If
  Greenhouse is reachable via WebFetch for a given company, use it —
  it's free and canonical for module 14 — but don't gate the pipeline
  on it.)
- **No cross-account parallelism.** Within an account, modules fan out
  via subagents. Across accounts, run sequentially.

---

## Reference

- Python project (source of truth for spec + schema):
  `~/code/account-research-agent/`
- Project state + history:
  `~/code/account-research-agent/CLAUDE.md`
- Module/property catalogue:
  `~/code/account-research-agent/INVENTORY.md`

When this command's spec disagrees with the project's `CLAUDE.md`, the
project file wins. Update both together.
