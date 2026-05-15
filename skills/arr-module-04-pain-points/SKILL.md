---
name: arr-module-04-pain-points
description: Module 4 of the Account Research Agent. Pure synthesis (no tools) — reads the outputs of modules 1, 3, 5, 6, 7, 9, 10, 12, 13, 14 and produces the Possible Pain Points section (intro + per-pain bullets + Pain Point Tags). Loaded directly by the /arr orchestrator after research fan-out.
---

# Module 4 — Strategic Narrative + Pain Tags

## Purpose

Synthesize a scannable analyst's brief from the 9 upstream module outputs. Output drives the **Possible Pain Points** page-body section and the **Pain Point Tags** Notion multi-select.

This is pure synthesis. **No tools.** All input must already be in the context passed by the orchestrator.

## Inputs

The orchestrator passes:
- `module_01_gate` — `regions_present`, size
- `module_03_revenue_model` — revenue model, customer segment, products
- `module_05_corporate_structure` — parent / child / standalone
- `module_06_structural_news` — recent structural event (if any)
- `module_07_trigger_events` — funding / rebrand / agency switch / AI initiative
- `module_09_creative_reality` — JD pain phrases + agencies
- `module_10_ad_library` — per-platform volume + audience classification
- `module_12_competitor_snapshot` — top 3 competitors + differentiators
- `module_13_industry_pulse` — category stories
- `module_14_hiring_signal` — headcount summary, important roles, layoffs
- `raw_research` (optional) — free text from upstream research_pass if available

## Output layout (v3.0.0)

Three parts:

1. **intro** — ONE sentence (or two short ones) framing the company's strategic moment in plain English. Not a tagline. Example: *"Oracle is mid-pivot from on-prem database vendor to AI-infrastructure hyperscaler, racing AWS and Azure for the same set of enterprise AI workloads."*
2. **pain_points** — 2–5 STRATEGIC PAINS. Each bullet has:
   - `label` — 2–6 word headline naming the pain (e.g. *"Category-perception battle vs. Meta Marketplace"*).
   - `body` — 1–3 sentences explaining what the company is trying to do strategically and why it's a creative/marketing challenge. Carry `[N]` markers after verifiable claims.
3. **tags** — 2–5 entries from the canonical vocabulary (below).

## Tag vocabulary (closed set — Notion `Pain Point Tags`)

Use only these exact strings:

- `creative production` — high ad volume / always-on demand-gen / surge capacity for launches
- `localization` — multi-market translation + adaptation
- `new territory` — recent or announced geographic expansion
- `strategy` — positioning / messaging help, not just execution
- `audience education` — teaching new buyers a non-obvious use case
- `competitive displacement` — winning audience away from a dominant incumbent
- `brand evolution` — rebrand / major repositioning / new visual identity
- `launch surge` — specific product launch driving short-term creative volume
- `AI receptivity` — company is publicly betting on AI in product/GTM
- `post-layoff overflow` — recent headcount cuts → agency offload becomes urgent

## Hard rules

- DO NOT write in cold-email voice (`"I noticed that you..."` / `"What if you..."`). This is an internal analyst note.
- DO NOT cite upstream module names (`"module_14 says..."`). The BDR doesn't care about plumbing.
- DO NOT mechanically infer pain from raw signal counts (`"they have 24 ads therefore production bottleneck"`). Tie pains to *what the company is trying to do strategically* — ads are downstream symptoms.
- DO NOT hedge with generic creative-needs filler. If the inputs don't support a specific named pain, OMIT it. Fewer better pains beats more vague pains.
- DO NOT repeat the same pain twice with different labels.
- Better to ship 2 tight pains than 5 mushy ones.
- Tags MUST be ones the pain bullets actually support.

## Citations

Every specific factual claim in the intro and in each pain-point body MUST carry a `[N]` marker. Each `[N]` references an entry in `citations`, numbered 1, 2, 3, … sequentially. Aim for 3–8 citations across intro + all bullets combined.

- `url` MUST be a URL that appears in one of the upstream module outputs (`citations[].url` or `sources`). Never invent a URL.
- `title` is `domain — claim` form, under 80 chars.
- Same source can be cited multiple times in the text but appears in `citations` only once.

## Output JSON schema

```json
{
  "type": "object",
  "required": ["intro", "pain_points", "tags", "citations", "sources", "confidence"],
  "properties": {
    "intro": {"type": "string", "minLength": 10},
    "pain_points": {
      "type": "array", "minItems": 1, "maxItems": 5,
      "items": {
        "type": "object",
        "required": ["label", "body"],
        "properties": {
          "label": {"type": "string", "minLength": 3, "maxLength": 120},
          "body": {"type": "string", "minLength": 20}
        }
      }
    },
    "tags": {
      "type": "array", "minItems": 0, "maxItems": 5,
      "items": {"type": "string", "enum": [
        "creative production", "localization", "new territory", "strategy",
        "audience education", "competitive displacement", "brand evolution",
        "launch surge", "AI receptivity", "post-layoff overflow"
      ]}
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

## Worked example — TBAuction

```json
{
  "intro": "TBAuction runs a vertical-auction marketplace in a category dominated by Meta Marketplace, eBay, and adjacent peer-to-peer selling apps [1].",
  "pain_points": [
    {
      "label": "Category-perception battle vs. Marketplace apps",
      "body": "Their conversion play is education-led: they need to teach sellers in specific high-value categories that auctions outperform 'list it on Marketplace' for those use cases — a non-obvious mental shift their target sellers haven't made yet [2]."
    },
    {
      "label": "Italy launch — new-market creative load",
      "body": "TBAuction is expanding into Italy [3], compounding the strategic creative challenge: they have to teach the same use-case shift in a new language and cultural context where neither the company nor the auction format has brand awareness."
    },
    {
      "label": "Always-on demand-gen across two markets",
      "body": "While ramping Italy, they still have to keep home-market always-on demand-gen alive [4] — the production load is now both higher-volume and more localized than before."
    }
  ],
  "tags": ["audience education", "competitive displacement", "localization", "new territory", "creative production"],
  "citations": [
    {"n": 1, "title": "tbauction.com — about", "url": "https://www.tbauction.com/about"},
    {"n": 2, "title": "techcrunch.com — auction platforms 2026", "url": "https://techcrunch.com/..."},
    {"n": 3, "title": "reuters.com — TBAuction Italy launch", "url": "https://www.reuters.com/..."},
    {"n": 4, "title": "tbauction.com — careers (creative roles)", "url": "https://careers.tbauction.com/"}
  ],
  "sources": [
    "https://www.tbauction.com/about",
    "https://techcrunch.com/...",
    "https://www.reuters.com/...",
    "https://careers.tbauction.com/"
  ],
  "confidence": "high"
}
```

## Confidence rubric

- `high` — research clearly supports specific named pains anchored in concrete moves/plays/shifts; most claims citable.
- `medium` — pain material present but growth play or conversion strategy inferred; some claims uncited.
- `low` — research thin; 1–2 cautious pains rather than padded filler.

The orchestrator-side `arr-writeback` skill renders `intro` as the first paragraph of **Possible Pain Points**, then one bulleted_list_item per pain (`**{label}** — {body}`), then a tag bullet listing the chosen pain tags, then writes `tags` to the **Pain Point Tags** Notion multi-select.
