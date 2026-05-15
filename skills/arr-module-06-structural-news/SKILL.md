---
name: arr-module-06-structural-news
description: Module 6 of the Account Research Agent. Surfaces last-6-month (or 12-month for big events) structural events — M&A, IPO, layoffs, bankruptcy — using a constrained vocabulary for the Structure Notes text property. Loaded by per-account research subagents inside /arr.
allowed-tools: WebSearch, WebFetch
---

# Module 6 — Structural News

## Purpose

Identify ONE significant structural event in the appropriate recency window (M&A close, IPO/SPAC, bankruptcy, mass layoffs, executive change, restructuring, market exit) and emit a short phrase from a **constrained vocabulary** for the Notion `Structure Notes` text property.

## Inputs

- `account_name`
- `today_date` — for recency cutoffs
- Optional output from module 5 (helps confirm acquisition mechanics)

## Searches to run

Use `WebSearch` 3–6 times.

1. `"<company> acquired" OR "<company> merger" 2026`
2. `"<company> IPO" OR "<company> SPAC"`
3. `"<company> layoffs"`
4. `"<company> restructuring" OR "<company> Chapter 11"`
5. Optional: `WebFetch` the highest-quality result for the date.

## Tiered recency policy

Today's date is provided in the subagent prompt. **Do not use your training-data sense of "recent."**

- **BIG EVENTS — 12-month window**: M&A close, IPO/SPAC, bankruptcy, mass layoffs (>5% of workforce OR >100 roles), executive change (CEO/CFO/CMO/CRO), acquisition-by-parent that ended brand independence.
- **RELEVANT NEWS — 6-month window**: smaller structural events (regional office moves, restructuring of a single division, smaller layoff rounds <5%).
- **Hard cutoff**: anything older than 12 months, or (for non-big events) older than 6 months → `structure_note=null`, `buying_implication=null`, `event_date=null`. Do not surface.

If a 3-month-old big event and a 2-month-old smaller event both qualify, **prefer the big event** (higher business significance).

`event_date` MUST be `YYYY-MM-DD`. If you cannot find a verifiable absolute date, drop the item — never write `"around 2025"` or `"recently"`.

## Constrained vocabulary for `structure_note`

Must be one of, or `null`:

- `recent IPO`
- `about to IPO`
- `merged with <COMPANY>` — substitute the actual counterparty name
- `acquired <COMPANY>` — substitute the acquired company's name
- `acquired by <COMPANY>` — substitute the acquiring company's name
- `split from <COMPANY>` — substitute the former parent's name
- `mass layoffs`
- `bankruptcy`
- `buying-frozen`
- `buying-friendly`
- `out of business`

## Placeholder-substitution rule (CRITICAL)

`X`, `Y`, `Z`, `<COMPANY>` are documentation placeholders only. **Never write them literally.**

- BAD: `"merged with X"`, `"acquired Y"`
- GOOD: `"merged with Salesforce"`, `"acquired Tegus"`, `"acquired by IBM"`

If you cannot identify the actual counterparty name from the research, set `structure_note=null` rather than writing a placeholder.

## `out of business` rule

Use when the company has ceased operations entirely, filed Chapter 7 (not Chapter 11 reorganization), or was fully absorbed such that the brand no longer exists. If Company X was acquired AND its products/brand have been sunset, prefer `out of business` over `acquired by Y` — operational reality trumps mechanic. For `out of business`, `buying_implication` MUST be `buying-frozen`.

## `buying_implication`

- `buying-frozen` — hiring freeze + cost-cutting (BAD outbound timing)
- `buying-friendly` — new funding / IPO proceeds / aggressive growth (GOOD timing)
- `null` — no clear directional implication

## Hard rules

- Routine product launches don't count. No padding.
- `event_summary` carries `[N]` markers after specific dates, numbers, and named parties.
- Citation rules: numbers sequential and contiguous, never invent URLs.

## Output JSON schema

```json
{
  "type": "object",
  "required": ["structure_note", "citations", "sources", "confidence"],
  "properties": {
    "structure_note": {"type": ["string", "null"]},
    "event_date": {"type": ["string", "null"]},
    "event_summary": {"type": ["string", "null"]},
    "buying_implication": {
      "type": ["string", "null"],
      "enum": ["buying-frozen", "buying-friendly", null]
    },
    "citations": {
      "type": "array", "minItems": 0, "maxItems": 12,
      "items": {
        "type": "object",
        "required": ["n", "title", "url"],
        "properties": {
          "n": {"type": "integer", "minimum": 1},
          "title": {"type": "string", "minLength": 1, "maxLength": 120},
          "url": {"type": "string"}
        }
      }
    },
    "sources": {"type": "array", "items": {"type": "string"}},
    "confidence": {"type": "string", "enum": ["high", "medium", "low"]}
  }
}
```

## Worked example — Twilio mass layoffs

```json
{
  "structure_note": "mass layoffs",
  "event_date": "2026-02-15",
  "event_summary": "Twilio laid off ~5% of workforce (~340 roles) in Feb 2026 [1], primarily in customer success and engineering [2].",
  "buying_implication": "buying-frozen",
  "citations": [
    {"n": 1, "title": "techcrunch.com — Twilio Feb 2026 layoffs", "url": "https://techcrunch.com/..."},
    {"n": 2, "title": "sec.gov — Twilio 8-K", "url": "https://www.sec.gov/..."}
  ],
  "sources": ["https://techcrunch.com/...", "https://www.sec.gov/..."],
  "confidence": "high"
}
```

## Worked example — no qualifying event

```json
{
  "structure_note": null,
  "event_date": null,
  "event_summary": null,
  "buying_implication": null,
  "citations": [],
  "sources": [],
  "confidence": "high"
}
```

## Confidence rubric

- `high` — verifiable absolute date + at least one authoritative source.
- `medium` — date approximate (month-precise only) or single source.
- `low` — date unclear → set `structure_note=null` instead.

The orchestrator-side `arr-writeback` skill writes `structure_note` to the Notion `Structure Notes` text property and renders `event_summary` as part of the News section (when present).
