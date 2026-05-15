---
name: arr-module-12-competitors
description: Module 12 of the Account Research Agent. Identifies the top 3 direct competitors with a one-line marketing differentiator each; produces the Competitor Landscape bullets. Loaded by per-account research subagents inside /arr.
allowed-tools: WebSearch, WebFetch
---

# Module 12 — Competitor Snapshot

## Purpose

Identify the top 3 **direct** competitors and a one-line marketing differentiator for each. Output drives the **Competitor Landscape** page-body section.

## Inputs

- `account_name`
- Customer segment / product hints from module 3 (use these to scope "direct competitor" rather than tangential adjacency)

## Searches to run

Use `WebSearch` 2–4 times.

1. `"<company> vs"` — surfaces head-to-head comparisons
2. `"<company> competitors" OR "<company> alternatives"`
3. `"<company> market share" "<industry>"` — only if step 1–2 are thin
4. Optional `WebFetch` of a G2/Capterra "alternatives" page if returned

## Hard rules

- **Exactly 3 competitors** in the output. If fewer than 3 are clearly direct, fill with the closest matches and set `confidence=low`.
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
      "type": "array", "minItems": 3, "maxItems": 3,
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

- `high` — three named competitors, each cited from an authoritative source.
- `medium` — three named but one differentiator is inferred.
- `low` — fewer than 3 clearly direct competitors; use closest matches.

The orchestrator-side `arr-writeback` skill renders each competitor as a bullet under **Competitor Landscape**: `**{name}** — {positioning_differentiator}`. Module 13's stories are appended after these bullets in the same section.
