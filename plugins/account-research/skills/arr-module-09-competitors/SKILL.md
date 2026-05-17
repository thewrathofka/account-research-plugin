---
name: arr-module-09-competitors
description: Module 9 of the Account Research Agent. Identifies the top 3 direct competitors with a one-line marketing differentiator each; produces the Competitor Landscape bullets. Loaded by per-account research subagents inside /arr.
allowed-tools: WebSearch, WebFetch
---

# Module 9 — Competitor Snapshot

## Purpose

Identify the top 3 **direct** competitors and a one-line marketing differentiator for each. Output drives the **Competitor Landscape** page-body section.

## Inputs

- `account_name`
- Customer segment / product hints from module 2 (use these to scope "direct competitor" rather than tangential adjacency)

## Searches to run

Use `WebSearch` 2–4 times.

1. `"<company> vs"` — surfaces head-to-head comparisons
2. `"<company> competitors" OR "<company> alternatives"`
3. `"<company> market share" "<industry>"` — only if step 1–2 are thin
4. Optional `WebFetch` of a G2/Capterra "alternatives" page if returned

## Hard rules

- **1–3 truly direct competitors** in the output. PREFER truly direct over a forced count of 3. If only 2 truly direct exist, return 2 and set `confidence=medium`. If only 1 exists (rare — usually means hyper-niche category), return 1 and set `confidence=low`. **DO NOT** pad with adjacent or tangential players just to hit a count of 3 — a fabricated competitor is worse than an honest gap for the BDR.
- **Direct competitors only** — same buying audience, overlapping product. Skip tangential players.
- `positioning_differentiator` must be marketing-relevant: positioning, audience tilt, channel mix, brand voice, B2C-vs-B2B angle. **Not** a feature-list comparison.
- Each `positioning_differentiator` carries one or two `[N]` citation markers tying the claim to a specific source.
- Citation rules: numbers sequential and contiguous, never invent URLs.

## Output JSON schema

```json
{
  "type": "object",
  "required": ["competitors", "citations", "sources", "confidence"],
  "properties": {
    "competitors": {
      "type": "array", "minItems": 1, "maxItems": 3,
      "items": {
        "type": "object",
        "required": ["name", "positioning_differentiator"],
        "properties": {
          "name": {"type": "string"},
          "positioning_differentiator": {"type": "string"}
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

## Worked example — Slack

```json
{
  "competitors": [
    {
      "name": "Microsoft Teams",
      "positioning_differentiator": "Bundled with Office 365 — wins by enterprise-default rather than by creative or community-led marketing [1]."
    },
    {
      "name": "Discord",
      "positioning_differentiator": "Community-first, voice-native; markets to creators and SMB teams rather than enterprise IT buyers [2]."
    },
    {
      "name": "Google Workspace Chat",
      "positioning_differentiator": "Bundled with Workspace; minimal standalone marketing — competes on suite economics, not channel-by-channel brand spend [3]."
    }
  ],
  "citations": [
    {"n": 1, "title": "microsoft.com — Teams positioning", "url": "https://www.microsoft.com/..."},
    {"n": 2, "title": "discord.com — about", "url": "https://discord.com/..."},
    {"n": 3, "title": "workspace.google.com — Chat", "url": "https://workspace.google.com/..."}
  ],
  "sources": [
    "https://www.microsoft.com/...",
    "https://discord.com/...",
    "https://workspace.google.com/..."
  ],
  "confidence": "high"
}
```

## Confidence rubric

- `high` — 3 competitors named, each with a sourced differentiator citing the competitor's own marketing or named industry coverage.
- `medium` — 3 competitors named but some differentiators are inferred / generic; OR 2 truly direct competitors returned (and you refused to pad).
- `low` — 1 truly direct competitor (very niche category); OR named 3 but had to reach to adjacent players for the 3rd because the category is small.

The orchestrator-side `arr-writeback` skill renders each competitor as a bullet under **Competitor Landscape**: `**{name}** — {positioning_differentiator}`. Module 13's stories are appended after these bullets in the same section.
