---
name: arr-module-07-creative
description: Module 7 of the Account Research Agent. Profiles the company's creative posture — verbatim JD pain phrases mined from job descriptions plus named agency relationships — and produces the Creative Posture paragraph. Loaded by per-account research subagents inside /arr.
allowed-tools: WebSearch, WebFetch
---

# Module 7 — Creative Reality (Lite)

## Purpose

Build a short profile of the company's *creative posture*: in-house creative role signals + named agency relationships. Emits the **Creative Posture** page-body paragraph.

*(Detailed in-house team breakdown by function requires LinkedIn employee data and is excluded from MVP.)*

## Inputs

- `account_name`
- `regions_present` from module 1 (use to scope job searches if available)

## Workflow (HARD STOP — at most 4 tool calls)

1. **One `WebSearch` for jobs.** Query: `"<company> careers" creative OR designer OR brand OR content`. Look at returned snippets (or `WebFetch` the careers page) for creative/design/marketing role titles and verbatim pain phrases ("scale creative", "manage external freelancer pool", "high-volume campaigns").
2. **Up to 3 `WebSearch` calls** for agency relationships:
   - `"<company> creative agency partner"`
   - `"<company> agency of record" OR "<company> in-house design team"`
   - Optional: one specific follow-up if the first two left a key gap. Keep each query under 100 characters.
3. STOP and produce JSON. Do NOT keep searching for more detail.

## Hard rules

- `creative_role_count`: a single integer. NEVER a range like `5-10`. If genuinely unknown, set to `0` with `confidence=low`.
- `jd_pain_phrases`: VERBATIM quotes from job descriptions, not paraphrases. If you can't find verbatim pain language, return `[]`. **No paraphrase.**
- `named_agencies`: only those confirmed via press or a company-claimed partnership. Empty list is fine.
- `creative_posture_summary`: 3–5 sentences for a Superside AE. Explain WHY this company might buy creative production at scale. Carry `[N]` markers after specific named agencies, role counts, and quoted JD phrases.
- Citation rules: numbers sequential and contiguous, never invent URLs.

## Output JSON schema

```json
{
  "type": "object",
  "required": ["creative_role_count", "jd_pain_phrases", "named_agencies",
               "creative_posture_summary", "citations", "sources", "confidence"],
  "properties": {
    "creative_role_count": {"type": "integer"},
    "jd_pain_phrases": {"type": "array", "items": {"type": "string"}},
    "named_agencies": {"type": "array", "items": {"type": "string"}},
    "creative_posture_summary": {"type": "string"},
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

## Worked example — Twilio

```json
{
  "creative_role_count": 8,
  "jd_pain_phrases": [
    "manage external freelancer pool of 30+",
    "scale creative production for high-volume campaigns"
  ],
  "named_agencies": ["Wieden+Kennedy", "Pentagram"],
  "creative_posture_summary": "Twilio runs a hybrid creative model: ~8 in-house designers focused on brand work, with significant freelancer overflow [1]. Uses Wieden+Kennedy for major campaigns and Pentagram for brand-system work [2]. JD language hints at production-bottleneck pain: roles ask to 'manage external freelancer pool of 30+' [3] and 'scale creative production for high-volume campaigns' [1].",
  "citations": [
    {"n": 1, "title": "twilio.com — careers (motion designer)", "url": "https://www.twilio.com/company/jobs/..."},
    {"n": 2, "title": "wk.com — Twilio case study", "url": "https://wk.com/..."},
    {"n": 3, "title": "twilio.com — careers (production manager)", "url": "https://www.twilio.com/company/jobs/..."}
  ],
  "sources": [
    "https://www.twilio.com/company/jobs/...",
    "https://wk.com/..."
  ],
  "confidence": "medium"
}
```

## Confidence rubric

- `high` — multiple verbatim JD pain phrases captured AND at least one confirmed named agency relationship AND specific role count from a primary source (careers page or LinkedIn jobs with low-noise match).
- `medium` — either JD pain phrases OR a named agency relationship, but not both; OR the role count is reasonable but not corroborated.
- `low` — generic creative-needs framing with no specific JD language and no named agency. Common for companies with no public careers page or thin web presence; that's the honest read — set low and move on.

The orchestrator-side `arr-writeback` skill renders `creative_posture_summary` as the **Creative Posture** paragraph on the page body and feeds `jd_pain_phrases` + `named_agencies` into module 4's synthesis context.
