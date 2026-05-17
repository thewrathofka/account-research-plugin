---
name: arr-module-11-hiring
description: Module 11 of the Account Research Agent. Counts open roles + classifies important marketing/AI/creative roles into tiers; applies location-aware in-scope (UK+EU+NA) gating for the `hiring` Buying Signal; surfaces layoff news for `downsizing`. Loaded by per-account research subagents inside /arr.
allowed-tools: WebSearch, WebFetch
---

# Module 11 — Hiring / Downsizing Signal

## Purpose

Determine if the company is actively hiring (especially creative/marketing/AI roles) or recently downsized; classify important roles into tiers; surface the location-aware `hiring` signal and the layoff-derived `downsizing` signal for Notion `Buying Signals`. Emits the **Headcount** subsection under Overview.

## Inputs

- `account_name`
- `regions_present` from module 1 (used to confirm in-scope locations)
- `today_date`

## Workflow

1. **Find the company's Greenhouse board (if any).** `WebSearch` `"<company> careers"`, then `WebFetch` the careers page. If the apply link points to `job-boards.greenhouse.io/<slug>/...` or `boards.greenhouse.io/<slug>`, then `WebFetch` the Greenhouse public API:

   ```
   https://boards-api.greenhouse.io/v1/boards/<slug>/jobs
   ```

   This is free, no auth, canonical for B2B SaaS. Use the JSON list to count roles, extract titles, and read `location.name`.

2. **Fall back to LinkedIn / general WebSearch.** If no Greenhouse board, `WebSearch` `"<company> open jobs"` + `WebFetch` the company's `/careers` page to count posted roles and titles.

3. **Layoff news.** Only if step 1–2 didn't already answer it: `WebSearch` `"<company> layoffs 2026"`. Don't waste a search if the layoff context is already clear from module 6's output.

## Important-role tiers (regex bank concept)

Classify each role title; first-match-wins:

- **`tier_1_marketing_ai`** — marketing / brand / creative / content / design × AI / ML / automation / transformation
  (e.g. *"Marketing AI & Transformation Strategy Lead"*, *"AI Creative Director"*)
- **`tier_2_senior_leadership`** — Head / VP / Director / Chief / CMO / CCO / SVP in marketing / brand / creative / content / design / growth / demand-gen / RevOps; plus level-implicit titles (Creative Director, Art Director, CMO standalone)
- **`tier_3_senior_creative_ic`** — Senior / Principal / Staff / Lead Designer / Motion Designer / Brand Designer / Copywriter / Content Strategist

A role matching Tier 1 does NOT double-count as Tier 2.

## Location-aware in-scope rule

For each important role, classify its `location` string:

- **IN-SCOPE**: UK + EU + NA (Superside GTM markets)
- **OUT-OF-SCOPE**: India, APAC, ME, LATAM, etc.
- **UNKNOWN**: no country qualifier (Remote, TBD)

`creative_marketing_roles_in_scope_count` = the count whose location is IN-SCOPE.

## Signal-trigger rules

- `headcount_signal="hiring"` **iff** `creative_marketing_roles_in_scope_count >= 3`
- `headcount_signal="downsizing"` **iff** `recent_layoffs_detected=true` (last 6 months)
- Both can be `null`. (Both can technically be present in `Buying Signals` simultaneously when both fire — the orchestrator emits whichever applies.)

If the company has many global marketing/creative roles but FEWER than 3 in UK/EU/NA, set `headcount_signal=null` and STILL mention the global activity in `headcount_summary` for context — just don't trigger the signal.

## Hard rules

- `active_open_roles_total`: a single integer. Prefer Greenhouse total when available (canonical, 3–5× more than LinkedIn for B2B SaaS).
- `creative_marketing_roles_count`: GLOBAL count across all geographies.
- `creative_marketing_roles_in_scope_count`: subset in UK + EU + NA.
- `important_roles_recently_closed`: leave empty (`[]`) in this Claude Code track — there's no SQLite snapshot ledger in this rewrite. (The Python track has snapshot diffing; this skill captures only the current state.)
- `headcount_summary`: 1–3 sentences. `[N]` markers after counts and named role titles.
- Citation rules: sequential, contiguous, never invent URLs.

### Summary body-text rules

- If `in_scope_count >= 3`: lead with the in-scope hiring (the buying signal). Name the most senior or AI-related role explicitly.
- If GLOBAL count is meaningful (≥3) but in-scope count <3: mention global activity for context, note it's outside GTM markets, do NOT trigger the signal.
- If both counts <3: brief 1-sentence summary, `headcount_signal=null`.

## Output JSON schema

```json
{
  "type": "object",
  "required": [
    "active_open_roles_total", "creative_marketing_roles_count",
    "creative_marketing_roles_in_scope_count",
    "recent_layoffs_detected", "headcount_signal", "headcount_summary",
    "citations", "sources", "confidence"
  ],
  "properties": {
    "active_open_roles_total": {"type": "integer"},
    "creative_marketing_roles_count": {"type": "integer"},
    "creative_marketing_roles_in_scope_count": {"type": "integer"},
    "creative_marketing_role_titles": {"type": "array", "items": {"type": "string"}},
    "recent_layoffs_detected": {"type": "boolean"},
    "layoff_summary": {"type": ["string", "null"]},
    "headcount_signal": {"type": ["string", "null"], "enum": ["hiring", "downsizing", null]},
    "headcount_summary": {"type": "string"},
    "important_roles_open": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["title", "tier"],
        "properties": {
          "title": {"type": "string"},
          "tier": {"type": "string", "enum": [
            "tier_1_marketing_ai",
            "tier_2_senior_leadership",
            "tier_3_senior_creative_ic"
          ]},
          "url": {"type": "string"},
          "location": {"type": "string"},
          "in_scope": {"type": ["boolean", "null"]}
        }
      }
    },
    "important_roles_recently_closed": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["title", "tier"],
        "properties": {
          "title": {"type": "string"},
          "tier": {"type": "string", "enum": [
            "tier_1_marketing_ai",
            "tier_2_senior_leadership",
            "tier_3_senior_creative_ic"
          ]}
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

## Worked example — AlphaSense (in-scope hiring)

```json
{
  "active_open_roles_total": 198,
  "creative_marketing_roles_count": 12,
  "creative_marketing_roles_in_scope_count": 4,
  "creative_marketing_role_titles": [
    "Marketing AI & Transformation Strategy Lead",
    "Senior Motion Designer"
  ],
  "recent_layoffs_detected": false,
  "layoff_summary": null,
  "headcount_signal": "hiring",
  "headcount_summary": "AlphaSense is actively hiring with 198 open roles on Greenhouse [1], 12 in marketing/creative/AI globally and 4 in UK + US. Notable open roles: a 'Marketing AI & Transformation Strategy Lead' [2] and 'Senior Motion Designer' [3] — strong creative-investment signal.",
  "important_roles_open": [
    {
      "title": "Marketing AI & Transformation Strategy Lead",
      "tier": "tier_1_marketing_ai",
      "url": "https://job-boards.greenhouse.io/alphasense/jobs/...",
      "location": "New York, NY",
      "in_scope": true
    },
    {
      "title": "Senior Motion Designer",
      "tier": "tier_3_senior_creative_ic",
      "url": "https://job-boards.greenhouse.io/alphasense/jobs/...",
      "location": "London, UK",
      "in_scope": true
    }
  ],
  "important_roles_recently_closed": [],
  "citations": [
    {"n": 1, "title": "alphasense — Greenhouse board", "url": "https://boards-api.greenhouse.io/v1/boards/alphasense/jobs"},
    {"n": 2, "title": "Marketing AI & Transformation Strategy Lead — AlphaSense", "url": "https://job-boards.greenhouse.io/alphasense/jobs/..."},
    {"n": 3, "title": "Senior Motion Designer — AlphaSense", "url": "https://job-boards.greenhouse.io/alphasense/jobs/..."}
  ],
  "sources": [
    "https://boards-api.greenhouse.io/v1/boards/alphasense/jobs",
    "https://job-boards.greenhouse.io/alphasense/jobs/..."
  ],
  "confidence": "high"
}
```

## Worked example — out-of-scope-only hiring

```json
{
  "active_open_roles_total": 60,
  "creative_marketing_roles_count": 8,
  "creative_marketing_roles_in_scope_count": 1,
  "creative_marketing_role_titles": ["Content Marketing Manager", "Brand Designer"],
  "recent_layoffs_detected": false,
  "layoff_summary": null,
  "headcount_signal": null,
  "headcount_summary": "Out of scope for the `hiring` signal — Acme has 8 marketing/content roles open globally but they concentrate in Bengaluru and Pune; in UK + US they have only 1 marketing posting [1].",
  "important_roles_open": [],
  "important_roles_recently_closed": [],
  "citations": [
    {"n": 1, "title": "acme — Greenhouse board", "url": "https://boards-api.greenhouse.io/v1/boards/acme/jobs"}
  ],
  "sources": ["https://boards-api.greenhouse.io/v1/boards/acme/jobs"],
  "confidence": "medium"
}
```

## Confidence rubric

- `high` — Greenhouse total + clean per-role locations + corroborated layoff status.
- `medium` — fallback to LinkedIn/careers page (totals approximate).
- `low` — no fetchable jobs page; layoff status unverified.

The orchestrator-side `arr-writeback` skill writes `headcount_signal` (when not null) to `Buying Signals` and renders `headcount_summary` as the **Headcount** subsection under Overview, optionally followed by bulleted important-role entries.
