---
name: arr-module-10-ads
description: Module 10 of the Account Research Agent. Best-effort ad library lookup (LinkedIn always; Meta gated by B2C/DTC/hybrid; TikTok gated by Gen-Z/lifestyle) via WebFetch — no Apify in the Claude Code rewrite. Produces Ads Running bullets under Creative Posture. Loaded by per-account research subagents inside /arr.
allowed-tools: WebSearch, WebFetch
---

# Module 10 — Ad Library (Best Effort via WebFetch)

## Purpose

Look up whether the company is currently advertising on LinkedIn, Meta, and TikTok ad libraries, classify the audience, and emit per-platform bullets for the **Creative Posture → Ads Running** subsection.

Track 1 (the Python project) uses Apify scrapers. **This Claude Code track uses `WebFetch` against the public ad-library pages.** Best-effort: if the page returns no results, that's the answer.

## Inputs

- `account_name`
- Optional product/audience hints from module 3 (helps classify B2C/DTC vs B2B)

## Step 1 — classify audience (no new searches)

Using context already available (account name + module 3 if provided):

- `primary`: `"B2B"` | `"B2C"` | `"hybrid"`
- `is_gen_z_lifestyle`: `true` ONLY if the company explicitly targets Gen-Z, influencer/creator ecosystems, lifestyle, fashion, fitness/wellness, or short-form-video-native categories. Enterprise software is **never** Gen-Z.

## Step 2 — LinkedIn ad library (ALWAYS)

`WebFetch` the LinkedIn Ad Library search for the company:

```
https://www.linkedin.com/ad-library/search?companyIds=<id>
```

If you don't have the company ID, try the company-name search form:

```
https://www.linkedin.com/ad-library/search?keyword=<company+name>
```

Extract: count of active ads, format mix (static / video / carousel), 1–3 sample ad URLs.

## Step 3 — Meta ad library (gated)

Call only if `audience.primary in {"B2C", "DTC", "hybrid"}` AND LinkedIn returned `ads_running > 0`.

```
https://www.facebook.com/ads/library/?active_status=active&ad_type=all&country=ALL&q=<company+name>
```

Otherwise emit a "not applicable" platform entry.

## Step 4 — TikTok ad library (gated)

Call only if `audience.is_gen_z_lifestyle=true` AND LinkedIn returned `ads_running > 0`.

```
https://library.tiktok.com/ads?region=all&start_time=&end_time=&adv_name=<company+name>
```

Otherwise emit a "not applicable" platform entry.

## Volume buckets

| Bucket | Count |
|---|---|
| `none` | 0 |
| `low` | 1–10 |
| `medium` | 11–50 |
| `high` | 51+ |

## Hard rules

- ALWAYS include all three platforms in `platforms`, in order: `linkedin`, `meta`, `tiktok`. Even when skipped — use `ads_running=0`, `volume="none"`, and a clear `"Not applicable — …"` note.
- `volume` MUST be `none`/`low`/`medium`/`high`. Match the count.
- `format_mix`: only formats you can verify from the ad-library page. Empty array is fine.
- `sources`: include the ad-library detail URLs you actually fetched.
- If `WebFetch` returns no data (page blocked, no ads, login wall): set `ads_running=0`, `volume="none"`, `note="Ad library returned no fetchable results"`, and `confidence="low"`.
- DO NOT make up ad counts. DO NOT scrape behind a login wall.
- Each `note` carries `[N]` citation markers when it references a specific sample ad URL.

## Output JSON schema

```json
{
  "type": "object",
  "required": ["audience_classification", "platforms", "citations", "sources", "confidence"],
  "properties": {
    "audience_classification": {
      "type": "object",
      "required": ["primary", "is_gen_z_lifestyle", "rationale"],
      "properties": {
        "primary": {"type": "string", "enum": ["B2B", "B2C", "hybrid"]},
        "is_gen_z_lifestyle": {"type": "boolean"},
        "rationale": {"type": "string"}
      }
    },
    "platforms": {
      "type": "array", "minItems": 3, "maxItems": 3,
      "items": {
        "type": "object",
        "required": ["platform", "ads_running", "volume", "note"],
        "properties": {
          "platform": {"type": "string", "enum": ["linkedin", "meta", "tiktok"]},
          "ads_running": {"type": "integer", "minimum": 0},
          "volume": {"type": "string", "enum": ["none", "low", "medium", "high"]},
          "format_mix": {
            "type": "array",
            "items": {
              "type": "object",
              "required": ["format", "count"],
              "properties": {
                "format": {"type": "string"},
                "count": {"type": "integer", "minimum": 0}
              }
            }
          },
          "note": {"type": "string"}
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

## Worked example — pure B2B (Moody's)

```json
{
  "audience_classification": {
    "primary": "B2B",
    "is_gen_z_lifestyle": false,
    "rationale": "Moody's serves banks, insurers, and institutional investors — pure B2B / financial-services audience."
  },
  "platforms": [
    {
      "platform": "linkedin",
      "ads_running": 12,
      "volume": "low",
      "format_mix": [
        {"format": "static", "count": 8},
        {"format": "video", "count": 3},
        {"format": "carousel", "count": 1}
      ],
      "note": "Product-demo and thought-leadership creative dominant [1]."
    },
    {
      "platform": "meta",
      "ads_running": 0,
      "volume": "none",
      "format_mix": [],
      "note": "Not applicable — pure B2B audience, Meta ad library skipped."
    },
    {
      "platform": "tiktok",
      "ads_running": 0,
      "volume": "none",
      "format_mix": [],
      "note": "Not applicable — not a Gen-Z/lifestyle audience."
    }
  ],
  "citations": [
    {"n": 1, "title": "linkedin.com — Moody's ad library", "url": "https://www.linkedin.com/ad-library/..."}
  ],
  "sources": ["https://www.linkedin.com/ad-library/..."],
  "confidence": "medium"
}
```

## Confidence rubric

- `high` — LinkedIn fetched successfully + correct gating decisions for Meta/TikTok.
- `medium` — LinkedIn fetched but partial data, or gating-skipped platforms only.
- `low` — `WebFetch` blocked / no fetchable data anywhere.

The orchestrator-side `arr-writeback` skill renders each platform as a bullet under **Creative Posture → Ads Running**: `**{platform}** — {ads_running} active ({volume}). {note}`.
