---
name: arr-module-10-industry
description: Module 10 of the Account Research Agent. Surfaces 2-3 last-90-day category-level stories that pass a Superside-relevance filter; appends to Competitor Landscape and may add `industry movement` to Buying Signals. Loaded by per-account research subagents inside /arr.
allowed-tools: WebSearch, WebFetch
---

# Module 10 — Industry Pulse

## Purpose

Identify 2–3 recent category-level news stories about the **industry** (not the company itself) that would plausibly affect this company's ability or willingness to buy Superside. Output appends to the **Competitor Landscape** section and may add `industry movement` to the Notion `Buying Signals` multi-select.

## Inputs

- `account_name`
- `today_date`
- `industry` / customer segment hints from modules 3 and 12

## Searches to run

Use `WebSearch` 3–6 times.

1. `"<industry> AI" 2026` — category-wide AI shift
2. `"<industry> consolidation" OR "<industry> acquisitions" 2026` — sector M&A wave
3. `"<industry> layoffs" 2026` — peer cost-cutting
4. `"<industry> marketing trends" 2026` — creative-format inflections
5. Optional `WebFetch` of authoritative analyst posts.

## Strict 90-day recency

The subagent prompt provides `Today is YYYY-MM-DD.` Use it as the anchor.

- **PREFERRED**: stories within last 90 days.
- **HARD CUTOFF**: anything older than 90 days does NOT belong in this output. If only older items exist, return an empty `stories` list and `confidence=low`.
- Every story must include an absolute date within the 90-day window. If the research doesn't surface a verifiable date, drop the story.

## Superside-relevance filter (CRITICAL — apply BEFORE choosing stories)

A story qualifies ONLY if it would plausibly change how (or whether) this company invests in creative/marketing OR shifts wider buying behaviour in their category.

**Qualifying themes:**
- Category-wide shifts that change marketing/creative strategy: AI in the category, new buying channels (e.g. TikTok shopping for ecommerce), brand-positioning trends competitors are responding to, creative-format inflections (short-form video, generative-AI ads), new regulatory constraints on creative content.
- Wider buying-environment shifts: peer layoffs, sector downturns triggering buying freezes, category consolidation creating winners/losers, market entrants disrupting incumbent ad spend.
- Major peer events (acquisitions, IPOs, layoffs) signaling sector-wide pressure or new budget — not single-company news.

**Do NOT include:**
- Generic industry news unrelated to marketing/creative strategy or buying.
- A single competitor's product launch unless it forces category-wide marketing repositioning.
- Routine funding rounds for ONE player (that's not `industry movement`).
- Macro news (Fed rate moves, geopolitics) unless explicitly tied to a sector buying freeze for this category.

## `industry_movement_detected` rule

`true` iff at least one story has `buying_implication="industry movement"`. The orchestrator-side `arr-writeback` skill then adds `industry movement` to the Notion `Buying Signals` multi-select.

`buying_implication` is `"industry movement"` only when the story implies the *category* is consolidating, AI-disrupted, going through a creative/marketing strategy shift, OR experiencing a wider buying freeze. Otherwise `null`.

## Hard rules

- 2–3 stories. If only 1 truly relevant story exists, include only it and set `confidence=medium`. 0 stories if nothing fits the window AND the relevance filter.
- The `industry` field captures the category as you see it (one short phrase).
- Each `headline` ends with a `[N]` citation marker for the source publication.
- Citation rules: numbers sequential and contiguous, never invent URLs.

## Output JSON schema

```json
{
  "type": "object",
  "required": ["industry", "stories", "industry_movement_detected", "citations", "sources", "confidence"],
  "properties": {
    "industry": {"type": "string"},
    "stories": {
      "type": "array", "minItems": 0, "maxItems": 3,
      "items": {
        "type": "object",
        "required": ["headline", "url"],
        "properties": {
          "headline": {"type": "string"},
          "url": {"type": "string"},
          "buying_implication": {
            "type": ["string", "null"],
            "enum": ["industry movement", null]
          }
        }
      }
    },
    "industry_movement_detected": {"type": "boolean"},
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

## Worked example — restaurant tech consolidation

```json
{
  "industry": "Vertical SaaS for restaurants",
  "stories": [
    {
      "headline": "Toast acquires xtraCHEF, signaling restaurant-tech consolidation [1]",
      "url": "https://techcrunch.com/...",
      "buying_implication": "industry movement"
    },
    {
      "headline": "Restaurant SaaS sector sees 30% spike in M&A activity in Q1 2026 [2]",
      "url": "https://www.restaurantbusiness.com/...",
      "buying_implication": "industry movement"
    }
  ],
  "industry_movement_detected": true,
  "citations": [
    {"n": 1, "title": "techcrunch.com — Toast acquires xtraCHEF", "url": "https://techcrunch.com/..."},
    {"n": 2, "title": "restaurantbusiness.com — Q1 2026 M&A spike", "url": "https://www.restaurantbusiness.com/..."}
  ],
  "sources": [
    "https://techcrunch.com/...",
    "https://www.restaurantbusiness.com/..."
  ],
  "confidence": "high"
}
```

## Confidence rubric

- `high` — 2–3 stories, all within the 90-day cutoff, each from a named outlet, each clearly Superside-relevant per the filter (category shift, buying-environment shift, or major peer event).
- `medium` — 1 truly relevant story + at most 1 borderline; OR 2 stories but one of them stretches the Superside-relevance filter.
- `low` — stories older than 90 days OR fail the relevance filter; OR zero stories returned (which is a valid honest output — do NOT pad with generic industry news to get to 2-3).

The orchestrator-side `arr-writeback` skill renders each story as a bullet appended to **Competitor Landscape**, and adds `industry movement` to `Buying Signals` iff `industry_movement_detected=true`.
