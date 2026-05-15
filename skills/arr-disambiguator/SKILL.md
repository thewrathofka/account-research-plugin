---
name: arr-disambiguator
description: Pre-dispatch skill for /arr. When an account name in the CRM is ambiguous (multiple unrelated companies share the name), runs 1-3 targeted WebSearches and returns the resolved entity with a one-line justification. The orchestrator passes the resolved entity into each per-module subagent so they don't research the wrong company.
allowed-tools: WebSearch
---

# arr-disambiguator — Resolve Ambiguous Account Names

## Purpose

Some company names in the CRM are ambiguous — multiple unrelated companies share a name. Researching the wrong entity produces high-quality but useless research. This skill resolves ambiguity BEFORE the 14-module fan-out, so every downstream skill receives the same entity.

Examples encountered in batch runs:
- **Brunswick** — Brunswick Corporation (NYSE:BC, marine/recreation, ~14K employees) vs. Brunswick Group (strategic comms PR firm, ~1.6K employees)
- **CAI** — Computer Aid, Inc. (IT services, Allentown PA, $1.4B rev) vs. CAI Pharma, CAI Asia, CAI International (logistics), Commissioning Agents Inc., etc.
- **Tide** — Tide Platform Ltd (UK SMB business banking fintech) vs. Tide (P&G laundry detergent brand)
- **Centric** — Centric Software (Dassault Systèmes apparel PLM) vs. Centric Consulting (Dayton OH mgmt consulting) vs. Centric NL (Dutch IT firm)

## Inputs

The orchestrator passes:
- `account_name` — the CRM record's account name
- Optional `crm_hints` — Industry/Region/Size/Notes from the Notion record that may narrow the field
- Optional `disambiguation_hint` — a free-text hint from the orchestrator if it pre-recognized the ambiguity (e.g. `"fintech, not detergent"`)

## When to invoke

The orchestrator should invoke this skill if:
1. `account_name` matches a known-ambiguous name from the list above (orchestrator's hard-coded watchlist), OR
2. `account_name` is a single common word (`Centric`, `Tide`, `Apex`, `Bridge`, `Stage`, `Core`) likely to collide, OR
3. The orchestrator's previous run flagged this account as `needs_review` with note "Possible duplicate" — re-running through disambiguation may resolve.

Otherwise, **skip the disambiguator** — most account names are not ambiguous and the cost isn't justified.

## Searches to run

Use `WebSearch` **2-3 times max**.

1. `"<account_name>"` (plain name) — see what comes up first.
2. `"<account_name> company headquarters"` — narrow to corporate entity.
3. (If still ambiguous) `"<account_name>" <crm_hint_industry>` or `"<account_name>" <crm_hint_region>` — narrow further.

Stop as soon as a single entity matches the CRM hints clearly.

## Hard rules

- **Pick exactly one entity.** No "could be either A or B" outputs. If genuinely ambiguous, set `resolution_confidence=low` and return your best guess with `note` explaining the ambiguity.
- **Do not invent** company details — only fields you actually saw in search results.
- **Match against CRM hints** before deciding. If the CRM record has `Priority Type=Priority B`, `Rep=Katarina`, and Industry=Fintech, prefer the fintech entity.
- Return the **legal/trading name** in `resolved_entity_name` (e.g. "Computer Aid, Inc." not just "CAI"). The downstream subagents use this name for their searches.

## Output JSON schema

```json
{
  "type": "object",
  "required": ["resolved_entity_name", "resolution_confidence", "evidence", "ruled_out", "sources"],
  "properties": {
    "resolved_entity_name": {"type": "string", "minLength": 3},
    "resolved_entity_short": {"type": "string", "description": "Short form to use in downstream search queries"},
    "resolution_confidence": {"type": "string", "enum": ["high", "medium", "low"]},
    "evidence": {"type": "string", "description": "One-sentence justification (legal name + hq + size band + industry)"},
    "ruled_out": {
      "type": "array",
      "description": "Other entities that share the name but were ruled out",
      "items": {
        "type": "object",
        "required": ["name", "reason"],
        "properties": {
          "name": {"type": "string"},
          "reason": {"type": "string"}
        }
      }
    },
    "note": {"type": ["string", "null"], "description": "Optional caveat (e.g. 'Two entities share this name — picking the larger/more BDR-relevant one')"},
    "sources": {"type": "array", "items": {"type": "string"}}
  }
}
```

## Worked example — Brunswick

```json
{
  "resolved_entity_name": "Brunswick Corporation",
  "resolved_entity_short": "Brunswick Corp",
  "resolution_confidence": "high",
  "evidence": "NYSE:BC marine/recreation conglomerate (Mercury Marine, Sea Ray, Boston Whaler), ~14,000 employees, Mettawa IL HQ. CRM Size=5000+ matches.",
  "ruled_out": [
    {"name": "Brunswick Group", "reason": "Strategic comms PR firm, ~1,600 employees — smaller than CRM Size band"}
  ],
  "note": null,
  "sources": [
    "https://en.wikipedia.org/wiki/Brunswick_Corporation",
    "https://www.brunswick.com/"
  ]
}
```

## Worked example — Tide

```json
{
  "resolved_entity_name": "Tide Platform Ltd",
  "resolved_entity_short": "Tide",
  "resolution_confidence": "high",
  "evidence": "UK SMB business banking fintech, London HQ, $1.5B unicorn valuation (Sep 2025), ~2,500 employees. CRM Rep=Katarina (BDR for fintech) + Industry hints align.",
  "ruled_out": [
    {"name": "Tide (P&G laundry detergent)", "reason": "Consumer product brand of Procter & Gamble — not an independent CRM-relevant entity"}
  ],
  "note": "Common collision — orchestrator should always pre-disambiguate for accounts named 'Tide'.",
  "sources": [
    "https://www.tide.co/about-us/",
    "https://en.wikipedia.org/wiki/Tide_(company)"
  ]
}
```

## Worked example — low confidence

```json
{
  "resolved_entity_name": "Apex Systems, Inc.",
  "resolved_entity_short": "Apex Systems",
  "resolution_confidence": "low",
  "evidence": "Subsidiary of ASGN Incorporated (now renamed Everforth, NYSE:EFOR). IT staffing, Glen Allen VA HQ. Multiple smaller 'Apex' entities exist (Apex AI, Apex Tool Group, Apex Fintech). CRM Size=5000+ best fits this entity.",
  "ruled_out": [
    {"name": "Apex AI", "reason": "Series B autonomous-driving startup, ~150 employees — too small"},
    {"name": "Apex Tool Group", "reason": "Hand tools manufacturer, ~7,000 employees — fits size but BDR notes say IT staffing context"}
  ],
  "note": "Verify with the BDR before outreach — name collision risk.",
  "sources": [
    "https://www.apexsystems.com/about-apex",
    "https://en.wikipedia.org/wiki/ASGN_Incorporated"
  ]
}
```

## How `/arr` uses the output

The orchestrator includes `resolved_entity_name` and `resolved_entity_short` in every per-module subagent prompt:

```
Research module N for account "{resolved_entity_name}" (Notion page ID {page_id}). 
Disambiguation note: {evidence}.
Use "{resolved_entity_short}" in your search queries.
```

This ensures all 11 module subagents (modules 1, 3, 5, 6, 7, 9, 10, 12, 13, 14 + module 4 synthesis) research the same entity.

## Skip-when guidance

DO NOT invoke this skill for unambiguous names. Most batch accounts (Stripe, Nike, BMW, Walmart, etc.) are fine without disambiguation. Use it only when:
- Name is in the orchestrator's watchlist.
- Name is a single common word.
- Previous run flagged the account as needs_review with duplicate/ambiguity language.
- Manual user-input disambiguation request.

## Confidence rubric

- `high` — clear single match with multiple corroborating signals (legal name + size + industry + region all align with CRM record).
- `medium` — single most-likely match identified, but only 1-2 corroborating signals.
- `low` — multiple plausible entities; orchestrator should treat the resolved entity as a best guess and flag the account as `needs_review` after research.
