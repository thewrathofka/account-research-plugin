# account-research

> Claude Code plugin — 14-module B2B account research pipeline for the Notion All Accounts CRM. Native Claude Code orchestration: slash command → parallel module subagents → unified writeback. Mirrors the output contract of the Python source-of-truth at `~/code/account-research-agent/`.

---

## What it does

Researches a single account or a batch from your Notion All Accounts CRM by running 11 specialized research modules in parallel against publicly-available sources (WebSearch + WebFetch), synthesizing the findings into a strategic narrative, and writing both **properties** and **a structured page-body brief** back to the Notion account record.

Output contract is byte-for-byte aligned with the Python `account-research-agent` so the same Notion downstream tooling (event detection, monthly batch alerts, etc.) keeps working.

---

## Install

### One-time setup

```bash
# 1. Clone or already have the repo at ~/code/account-research-plugin/
cd ~/code/account-research-plugin

# 2. Symlink into Claude Code's user-scope plugin directory
ln -s ~/code/account-research-plugin ~/.claude/plugins/account-research

# 3. Verify Claude Code sees it
# Open Claude Code, run /plugin list — you should see "account-research" listed.
```

Alternative: `/plugin install ~/code/account-research-plugin` from inside Claude Code.

### Required setup in Notion

Create a permanent view in the All Accounts database (DB ID `6d510b5a-9c8f-490f-8600-429184341edc`) named **"Unresearched Priority B"** with:
- Filter: `Rep is <your name>` AND `Priority Type is Priority B` AND `Last Researched is empty`
- Sort: `Account Name` ASC

The `/arr` batch mode queries this view as its canonical source. Without it, batch mode falls back to the unfiltered DB query which is capped at 100 results by the MCP `notion-query-database-view` tool.

---

## Usage

```bash
# Single account
/arr Stripe

# Single account, dry-run (returns planned writeback without touching Notion)
/arr Stripe --dry-run

# Batch — all unresearched Priority B accounts for the default rep (Katarina)
/arr --batch

# Batch with overrides
/arr --batch --rep Katarina --priority "Priority B" --max 5
/arr --batch --since 30 --label "monthly-2026-05"
```

Default filters: `--rep Katarina`, `--priority "Priority A"`, `--since 30` (days since last research).

---

## Agent diagram

```
/arr (slash command)
      │
      ▼
┌─────────────────────────────┐
│  Orchestrator (this command) │  ← queries "Unresearched Priority B" Notion view
└─────────────────────────────┘
      │
      │  per-account (sequential across accounts, parallel within)
      │
      ├─► arr-disambiguator       (only for ambiguous names: Brunswick, CAI, Tide, …)
      │
      ├─► arr-module-01-gate      (GATE — EU/NA presence check; blocks if fail)
      │
      ├─►  Parallel fan-out:
      │       ├─► arr-module-03-revenue
      │       ├─► arr-module-05-corporate
      │       ├─► arr-module-06-structural-news
      │       ├─► arr-module-07-triggers
      │       ├─► arr-module-09-creative
      │       ├─► arr-module-10-ads
      │       ├─► arr-module-12-competitors
      │       ├─► arr-module-13-industry
      │       └─► arr-module-14-hiring
      │
      ├─► arr-module-04-pain-points  (synthesis — reads all 9 module outputs)
      │
      ├─► arr-page-assembly       (pure logic — builds Notion block payloads)
      │
      ├─► arr-writeback           (single notion-update-page + notion-create-pages call)
      │
      └─► arr-format-verifier     (post-write QA — re-fetches and validates)
                │
                └─► if FAIL → re-dispatch failing modules + arr-writeback
```

---

## Tool-to-skill matrix

| Skill | WebSearch | WebFetch | Notion search | Notion fetch | Notion write | notion-create-comment |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| `/arr` (orchestrator) | | | ✓ | ✓ | ✓ | ✓ |
| arr-disambiguator | ✓ | | | | | |
| arr-module-01-gate | ✓ | ✓ | | | | |
| arr-module-03-revenue | ✓ | ✓ | | | | |
| arr-module-04-pain-points | (synthesis — no tools) | | | | | |
| arr-module-05-corporate | ✓ | ✓ | | | | |
| arr-module-06-structural-news | ✓ | ✓ | | | | |
| arr-module-07-triggers | ✓ | ✓ | | | | |
| arr-module-09-creative | ✓ | ✓ | | | | |
| arr-module-10-ads | ✓ | ✓ | | | | |
| arr-module-12-competitors | ✓ | ✓ | | | | |
| arr-module-13-industry | ✓ | ✓ | | | | |
| arr-module-14-hiring | ✓ | ✓ | | | | |
| arr-page-assembly | (pure logic — no tools) | | | | | |
| arr-writeback | | ✓ | | ✓ | ✓ | ✓ |
| arr-format-verifier | | | | ✓ | | |

---

## Notion output contract

### Properties (agent-owned — always written every run)

| Property | Type | Module | Notes |
|---|---|---|---|
| `Size` | select | 1 | `<1000` / `1000-2000` / `2000-5000` / `5000+` (deterministic from employee count integer) |
| `Buying Signals` | multi-select | 7+13+14 | overwrite semantics — every run sets the full list including empty |
| `Pain Point Tags` | multi-select | 4 | overwrite semantics |
| `Structure Notes` | text | 6 | constrained vocabulary |
| `sister/child` | text | 5 | comma-separated sibling/child brand names |
| `Parent` | text | 5 | parent name; or own name if standalone-with-children; or empty |
| `Needs Attention` | multi-select | event detection | **append-only** — humans clear it |
| `date:Last Researched:start` | date | always | today |
| `Research Confidence` | select | always | `high` / `medium` / `low` / `failed` |
| `Research Status` | select | always | `done` / `needs_review` / `failed` / `out_of_scope` |

### Properties NEVER touched by the agent

- `Buying Intent` (BDR-managed Unify/Sales Nav data)
- `Prospecting Status` (BDR conversation state: Prospecting/SQL/SAL/Qualified/Neglected)
- `Lead Signal`, `Temperature`, `Last Touch Point`, `New Hire`, `Strategy`, `Cluster`, `Uncovered`, `Focused`, `Last Hygiene Check`, `Attention Acknowledged At`, `Unify Last Signal`, `Notes`, `Rep`, `Priority Type`, `Account Name`

### Page body section order (mandatory — orchestrator parses by exact name)

```
## Research — YYYY-MM-DD          (heading_2)
### Overview                       (heading_3)
#### Headcount                    (heading_4, subsection)
### Possible Pain Points           (heading_3)
### News                           (heading_3)
###   funding round / AI initiative / etc.  (heading_3 per-signal subheadings under News)
### Creative Posture               (heading_3)
#### Ads Running                  (heading_4, subsection)
### Competitor Landscape           (heading_3)
```

Body is wiped and rewritten on every run (orchestrator does NOT append alongside stale blocks).

---

## Failure modes encoded into the plugin

These are the failure modes observed across 100 batch runs in May 2026. Each is now defended against by the skills design:

| # | Failure | Defense |
|---|---|---|
| **A** | Properties writeback skipped (body written, properties empty) | `arr-format-verifier` post-write re-fetch catches and re-dispatches |
| **B** | Body format drift (non-canonical section structure) | `arr-format-verifier` validates section names against canonical list |
| **C** | Agent writes to human-managed `Prospecting Status` | Explicit forbid in `arr-writeback` hard rules + verifier flag |
| **D** | Parent / sister-child field swap | `arr-module-05-corporate` decision tree + verifier swap-detection |
| **E** | Stream idle timeout / partial response | Verifier catches it after the fact — partial writes still get repaired |
| **F** | Child accounts flagged as duplicates | (Document in module 5; orchestrator decision tree) |
| **G** | WebFetch denied silent fallback | Each module skill documents its fallback chain |
| **H** | Pagination cap on Notion view query (100 results) | Canonical "Unresearched Priority B" view (set up at install) keeps the batch <100 |
| **I** | Disambiguation absent | `arr-disambiguator` skill + ambiguous-name watchlist in orchestrator |

---

## File structure

```
account-research/
├── .claude-plugin/
│   └── plugin.json
├── README.md                              ← you are here
├── commands/
│   └── arr.md                             ← orchestrator
├── skills/
│   ├── arr-disambiguator/                 ← pre-dispatch resolver
│   ├── arr-module-01-gate/                ← 14-module pipeline starts here
│   ├── arr-module-03-revenue/
│   ├── arr-module-04-pain-points/         ← synthesis (no tools)
│   ├── arr-module-05-corporate/
│   ├── arr-module-06-structural-news/
│   ├── arr-module-07-triggers/
│   ├── arr-module-09-creative/
│   ├── arr-module-10-ads/
│   ├── arr-module-12-competitors/
│   ├── arr-module-13-industry/
│   ├── arr-module-14-hiring/
│   ├── arr-page-assembly/                 ← pure block-builder (no tools)
│   ├── arr-writeback/                     ← single Notion write chokepoint
│   └── arr-format-verifier/               ← post-write QA
└── tests/
    └── smoke-test.md                      ← how to validate after install
```

---

## Source of truth

When this plugin's spec disagrees with the Python project's `CLAUDE.md`, the Python project wins. Update both together.

- Python project: `~/code/account-research-agent/`
- Project state + history: `~/code/account-research-agent/CLAUDE.md`
- Module/property catalogue: `~/code/account-research-agent/INVENTORY.md`
- Schema constants: `~/code/account-research-agent/crm.py` (lines 52–84)
- Parent/sister decision tree: `~/code/account-research-agent/tasks/module_05.py` (lines 22–48)
- Section order: `~/code/account-research-agent/orchestrator.py` (lines 499–514)

---

## What this plugin deliberately does NOT do

- **No scheduled runs.** No GHA, no cron, no `/schedule` registration. Only fires on `/arr`.
- **No cost tracking.** No `--cost-summary`, no SQLite log, no per-call accounting. The Python project tracks that.
- **No paid third-party APIs by default.** Tavily / Apify / jobspy / Greenhouse ATS are replaced with `WebSearch` + `WebFetch`. (Greenhouse via WebFetch is fine when reachable — it's free and canonical for module 14 — but not gated on.)
- **No cross-account parallelism.** Within an account, modules fan out via subagents. Across accounts, run sequentially. (Notion rate limits + the cost of debugging interleaved output isn't worth it for personal use.)

---

## Known limitations

1. **Stream idle timeouts.** Background subagents can stall after ~5 minutes when running many WebSearches in series. `arr-format-verifier` catches the resulting partial writes after the fact, but per-subagent budgeting (≤8 searches) is still important.
2. **Laptop sleep kills in-flight subagents.** No way to fix from inside Claude Code. Verifier catches it on next-run resume.
3. **MCP pagination.** The `notion-query-database-view` tool caps at 100 results with no cursor passthrough. The "Unresearched Priority B" view in Notion is the workaround.
4. **WebFetch denied on /careers.** Many corporate careers pages (Workday/Greenhouse JS) block automation. Module 14's skill documents the fallback chain (LinkedIn Jobs → Glassdoor → Indeed).

---

## Versioning

| Version | Date | Notes |
|---|---|---|
| 1.0.0 | 2026-05-13 | Initial scaffold (11 module skills + arr-page-assembly + arr-writeback) |
| 1.1.0 | 2026-05-15 | Added `arr-format-verifier` + `arr-disambiguator` skills. Wired both into orchestrator. Explicit Prospecting Status forbid in arr-writeback. README + smoke test added. Plugin renamed `account-research-agent` → `account-research`. |

---

## License

Private. Shared with team only.
