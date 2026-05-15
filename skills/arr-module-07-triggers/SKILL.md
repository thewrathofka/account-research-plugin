---
name: arr-module-07-triggers
description: Module 7 of the Account Research Agent. Detects last-90-day buying-signal triggers (funding round / active creative jobs / rebrand or campaign / agency switch / AI initiative) and produces the News-section trigger context. Loaded by per-account research subagents inside /arr.
allowed-tools: WebSearch, WebFetch
---

# Module 7 — Trigger Events (Last 90 Days)

## Purpose

Detect time-sensitive triggers in the last 90 days and emit tags for the Notion `Buying Signals` multi-select plus narrative context for the **News** page-body section.

## Inputs

- `account_name`
- `today_date` — for the strict 90-day cutoff

## Searches to run

Use `WebSearch` 4–7 times, one per category.

1. `"<company> funding" OR "<company> Series" 2026` — funding round
2. `"<company> hiring announcement" OR "<company> creative team"` — active creative jobs (announcement-level)
3. `"<company> rebrand" OR "<company> campaign launch"` — rebrand/campaign
4. `"<company> agency RFP" OR "<company> agency review"` — agency switch
5. `"<company> AI" 2026` (filter for product/GTM AI launches) — AI initiative

`WebFetch` only the press releases / announcements that anchor a specific date.

## Strict 90-day recency

The subagent prompt includes `Today is YYYY-MM-DD.` Use it as the anchor. Hard cutoff: any event older than 90 days from today MUST be dropped, even if it would be a strong signal otherwise.

Every trigger MUST carry a verifiable absolute date (YYYY-MM-DD) in the research. If you cannot find the date, drop the trigger. Do not write `"in early 2025"` or `"recently"`.

If nothing qualifies, return `triggers_detected=[]` with `confidence=low`. Do not pad.

## Trigger vocabulary (closed set — Notion `Buying Signals`)

`triggers_detected` MUST contain only these exact strings:

- `funding round`
- `active creative jobs`
- `rebrand/campaign`
- `agency switch`
- `AI initiative`

**Do NOT include** `new marketing/brand/creative leader` — excluded from MVP.

`active creative jobs` is set ONLY for a press release or notable hiring announcement (e.g. *"company announces 50-person creative team buildout"*). Routine job listings belong to module 14, not 7.

## Hard rules

- Empty array is valid output if nothing fits the 90-day window.
- Each `trigger_details` entry: exactly `trigger`, `summary` (1 sentence), `url`.
- Every `summary` must reference an absolute date within 90 days.
- Carry `[N]` citation markers after dates, dollar amounts, lead investor names, etc.
- Never invent triggers to fill the schema.
- Do NOT write to `Buying Intent` — that property is human-only since 2026-05-11.

## Output JSON schema

```json
{
  "type": "object",
  "required": ["triggers_detected", "trigger_details", "citations", "sources", "confidence"],
  "properties": {
    "triggers_detected": {
      "type": "array",
      "items": {
        "type": "string",
        "enum": ["funding round", "active creative jobs",
                 "rebrand/campaign", "agency switch", "AI initiative"]
      }
    },
    "trigger_details": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["trigger", "summary", "url"],
        "properties": {
          "trigger": {"type": "string"},
          "summary": {"type": "string"},
          "url": {"type": "string"}
        }
      }
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

## Worked example — funding + AI initiative

```json
{
  "triggers_detected": ["funding round", "AI initiative"],
  "trigger_details": [
    {
      "trigger": "funding round",
      "summary": "Raised $50M Series C led by Sequoia on 2026-03-12, earmarked for AI expansion [1].",
      "url": "https://techcrunch.com/..."
    },
    {
      "trigger": "AI initiative",
      "summary": "Announced AI-powered marketing copilot in Q1 2026 earnings on 2026-04-22 [2].",
      "url": "https://investors.example.com/..."
    }
  ],
  "citations": [
    {"n": 1, "title": "techcrunch.com — Series C funding", "url": "https://techcrunch.com/..."},
    {"n": 2, "title": "investors.example.com — Q1 2026 earnings call", "url": "https://investors.example.com/..."}
  ],
  "sources": [
    "https://techcrunch.com/...",
    "https://investors.example.com/..."
  ],
  "confidence": "high"
}
```

## Worked example — nothing in window

```json
{
  "triggers_detected": [],
  "trigger_details": [],
  "citations": [],
  "sources": [],
  "confidence": "low"
}
```

## Confidence rubric

- `high` — multiple triggers with hard dates and primary-source URLs.
- `medium` — one trigger with a credible single source.
- `low` — nothing within 90 days, or only weakly-dated candidates.

The orchestrator-side `arr-writeback` skill appends `triggers_detected` to the Notion `Buying Signals` multi-select and renders each `trigger_details.summary` as a bullet under the News section.
