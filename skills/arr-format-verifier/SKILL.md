---
name: arr-format-verifier
description: Post-write validator for /arr. Re-fetches a freshly-researched Notion page and confirms (a) all required properties were written, (b) the body uses the canonical PMG section structure, (c) Buying Signals/Pain Point Tags/Research Status values are from the closed vocabularies, and (d) Prospecting Status was NOT touched. Returns pass/fail with a structured diagnostic. Catches false-success returns from arr-writeback before the batch is reported done.
allowed-tools: mcp__claude_ai_Notion__notion-fetch
---

# arr-format-verifier — Post-Write QA

## Purpose

After `arr-writeback` finishes for an account, this skill **re-fetches** the page and validates the writeback actually landed in canonical form. Catches the failure modes that surfaced across 100 batch runs:

- **Failure A** — `arr-writeback` returned "success" but skipped properties (Last Researched/Research Confidence/Parent/Structure Notes empty). Verifier fails the page.
- **Failure B** — body content was written in a non-canonical structure (`# H1` + freeform `## H2` instead of canonical `## Research — date` + `### Overview / ...`). Verifier fails the page.
- **Failure C** — `Prospecting Status` was touched (it's BDR-managed, never agent-owned). Verifier fails the page.
- **Failure D** — Parent and sister/child swapped (parent name written to sister/child or vice versa). Verifier flags as warning.

When verifier fails, the orchestrator (`/arr`) re-dispatches the account in **fix-mode** (a single targeted re-run rather than a full 14-module re-research).

## Inputs

The orchestrator passes:
- `notion_page_id` — the freshly-written page
- `today_iso` — today's date in `YYYY-MM-DD` (for Last Researched check)
- `expected_account_name` — for sanity check against the page title

This skill has NO write tools and MUST NOT mutate Notion.

## Workflow

### 1. Fetch the page

Call `notion-fetch` on `notion_page_id`. Read both properties AND content.

### 2. Property checks

Validate each of these. Each failure adds a `diagnostic` line to the output.

| Check | Required | Pass criterion |
|---|---|---|
| `date:Last Researched:start` | Yes | Equals `today_iso` |
| `Research Confidence` | Yes | One of: `high`, `medium`, `low`, `failed` |
| `Research Status` | Yes | One of: `done`, `needs_review`, `failed`, `out_of_scope` |
| `Research Status` not in `{Qualified, Prospecting, SQL, SAL, Neglected}` | Yes | Hard fail if any of these appear in `Research Status` — they belong to `Prospecting Status` |
| `Size` (skip if gate failed) | If Status ≠ out_of_scope | One of: `<1000`, `1000-2000`, `2000-5000`, `5000+` |
| `Buying Signals` (if non-empty) | No | Every value ∈ `{funding round, active creative jobs, rebrand/campaign, agency switch, AI initiative, industry movement, hiring, downsizing}` |
| `Pain Point Tags` (if non-empty) | No | Every value ∈ `{creative production, localization, new territory, strategy, audience education, competitive displacement, brand evolution, launch surge, AI receptivity, post-layoff overflow}` |
| `Buying Intent` | Yes | UNCHANGED — the verifier records its value but does not gate on it; the orchestrator should snapshot `Buying Intent` pre-run and compare post-run |
| `Parent` vs `sister/child` swap detection | No (warning) | If `sister/child` contains a single well-known parent-style name like "DCC plc" / "Koch Industries" / "Lloyds Banking Group" / etc., AND `Parent` is empty, flag as `WARNING: likely swap` |

### 3. Body section checks

Fetch the page's child blocks. Validate:

| Check | Pass criterion |
|---|---|
| Top heading exists | First non-comment block is a `heading_2` with text matching `^## Research — \d{4}-\d{2}-\d{2}( — .+)?$` |
| No `heading_1` blocks | Body uses `heading_2` and `heading_3` only. Any `heading_1` is a fail (Failure B signature). |
| Section names match canonical | Section headings (heading_2) must be from: `Research — <date>`, `Overview`, `Possible Pain Points`, `News`, `Creative Posture`, `Competitor Landscape`. Subsection headings (heading_3) must be from: `Headcount`, `Ads Running`, `funding round`, `active creative jobs`, `rebrand/campaign`, `agency switch`, `AI initiative`, `industry movement`, `hiring`, `downsizing`. Anything else is a fail. |
| Section ORDER | Canonical order: Overview → (Headcount) → Possible Pain Points → News → (per-signal subheadings) → Creative Posture → (Ads Running) → Competitor Landscape. Out-of-order is a warning, not fail. |
| Section presence | At minimum: Overview AND Possible Pain Points must exist when status=done. (News, Creative Posture, Competitor Landscape recommended; absent is a warning.) |
| No `Sources:` global heading | Citations are inline-only since 2026-05-12. A `Sources` heading at page bottom is a fail. |

### 4. Gate-fail short-circuit

If `Research Status = out_of_scope`, ONLY validate:
- `Last Researched` set
- `Research Confidence` set (typically `high`)
- A single paragraph block explaining the gate-fail reason

Skip all other body checks. Return pass.

### 5. Compute overall result

```
result = "pass"  iff zero hard fails
result = "fail"  iff any hard fail
warnings = list of warning-level findings (do not flip result to fail)
```

### 6. Return structured output

```json
{
  "type": "object",
  "required": ["page_id", "account_name", "result", "fails", "warnings"],
  "properties": {
    "page_id": {"type": "string"},
    "account_name": {"type": "string"},
    "result": {"type": "string", "enum": ["pass", "fail"]},
    "fails": {"type": "array", "items": {"type": "string"}},
    "warnings": {"type": "array", "items": {"type": "string"}},
    "property_snapshot": {
      "type": "object",
      "description": "Key properties as written, for the orchestrator's summary line.",
      "properties": {
        "Research Status": {"type": ["string", "null"]},
        "Research Confidence": {"type": ["string", "null"]},
        "Last Researched": {"type": ["string", "null"]},
        "Size": {"type": ["string", "null"]},
        "Buying Signals": {"type": "array", "items": {"type": "string"}},
        "Pain Point Tags": {"type": "array", "items": {"type": "string"}},
        "Parent": {"type": ["string", "null"]},
        "sister/child": {"type": ["string", "null"]}
      }
    }
  }
}
```

## Worked example — pass

```json
{
  "page_id": "3523435e-7148-81d7-bbf7-c9b6b6d5fd21",
  "account_name": "Centric Consulting",
  "result": "pass",
  "fails": [],
  "warnings": [],
  "property_snapshot": {
    "Research Status": "done",
    "Research Confidence": "medium",
    "Last Researched": "2026-05-15",
    "Size": "1000-2000",
    "Buying Signals": ["AI initiative", "hiring", "industry movement"],
    "Pain Point Tags": ["AI receptivity", "audience education", "competitive displacement", "brand evolution"],
    "Parent": "none",
    "sister/child": "none"
  }
}
```

## Worked example — fail (Failure A + B together)

```json
{
  "page_id": "3523435e-7148-81de-9939-c6394e4d4183",
  "account_name": "Trane Technologies",
  "result": "fail",
  "fails": [
    "date:Last Researched:start is empty (expected 2026-05-15)",
    "Research Confidence is empty",
    "Parent is empty",
    "Body contains heading_1 'Trane Technologies plc (NYSE: TT)' — canonical format uses heading_2 only",
    "Section name 'Why Now' is not canonical (allowed: Research — date, Overview, Possible Pain Points, News, Creative Posture, Competitor Landscape)"
  ],
  "warnings": [],
  "property_snapshot": {
    "Research Status": "done",
    "Research Confidence": null,
    "Last Researched": null,
    "Size": "5000+",
    "Buying Signals": ["AI initiative", "active creative jobs", "industry movement", "hiring"],
    "Pain Point Tags": ["creative production", "audience education", "AI receptivity", "brand evolution"],
    "Parent": null,
    "sister/child": null
  }
}
```

## Worked example — fail (Failure C — Prospecting Status touched)

```json
{
  "page_id": "...",
  "account_name": "Foodhub",
  "result": "fail",
  "fails": [
    "Research Status is 'Qualified' — that's a Prospecting Status value. Research Status must be one of: done, needs_review, failed, out_of_scope."
  ],
  "warnings": [
    "Prospecting Status was set to 'Qualified' by the writeback. Prospecting Status is BDR-managed and should not be written by the agent."
  ],
  "property_snapshot": { "...": "..." }
}
```

## Hard rules

- This skill **never writes** to Notion. It is read-only QA.
- Always fail when canonical structure is violated — the orchestrator depends on this signal to trigger fix-mode dispatch.
- The orchestrator MUST NOT report a batch as "done" until format-verifier has passed each account.
- If `notion-fetch` errors, return `result=fail` with `fails=["could not fetch page: <error>"]`.
