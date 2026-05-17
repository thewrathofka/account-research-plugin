---
name: arr-module-04-corporate
description: Module 4 of the Account Research Agent. Classifies the company as standalone / subsidiary / parent + PE ownership; populates the Parent and sister/child Notion text properties with the self-name rule applied. Loaded by per-account research subagents inside /arr.
allowed-tools: WebSearch, WebFetch
---

# Module 4 — Corporate Structure

## Purpose

Determine whether the company is **standalone**, a **subsidiary** of another company, or a **parent** that owns notable child brands; flag PE ownership; list notable sister/child brands. Outputs feed the Notion `Parent` and `sister/child` text properties.

## Inputs

- `account_name`
- Optional region/HQ context from module 1

## Searches to run

Use `WebSearch` 2–4 times.

1. `"<company> parent company"` or `"<company> subsidiary of"`
2. `"<company> acquired by" OR "<company> acquisition"` — catches subsidiary case
3. `"<company> acquired"` (no `by`) — catches parent case (companies it owns)
4. `"<company> private equity owner"` — only if step 1–3 hinted at ownership

Optional `WebFetch` the most authoritative result (SEC filing, press release, Wikipedia infobox).

## Classification rules

`structure_type` MUST be one of:

- **`subsidiary`** — owned by another company (e.g. Tableau is a subsidiary of Salesforce).
- **`parent`** — owns at least one notable subsidiary OR has acquired another brand it still operates. A single notable acquisition is enough. Example: AlphaSense acquired Tegus → AlphaSense is `parent`.
- **`standalone`** — no parent AND no notable child/sister brands.

## Self-name rule (CRITICAL)

For the Notion `Parent` field:
- If `structure_type=parent` → write the **company's own name**.
- If `structure_type=subsidiary` → write the parent's name.
- If `structure_type=standalone` → leave empty (null).

**Consistency lock:** if `notable_sister_or_child_brands` is non-empty, `structure_type` MUST be `parent` — they cannot disagree. The orchestrator enforces this as a sanity check; the model frequently misclassifies a parent-with-one-child as `standalone` (e.g. AlphaSense after acquiring Tegus). When in doubt, if you can name at least one child brand, classify as `parent`.

## Hard rules

- `notable_sister_or_child_brands`: include only brands relevant to marketing/creative buying decisions. Skip obscure internal subsidiaries. Empty list is fine.
- Use `null` for fields you cannot confirm. DO NOT guess parent companies from name similarity or industry adjacency.
- `pe_owner` is null unless `is_pe_owned=true`.

## Citation rules

`[N]` markers, sequential, contiguous; every `url` must come from a tool result this run; never invent.

## Output JSON schema

```json
{
  "type": "object",
  "required": ["structure_type", "is_pe_owned", "citations", "sources", "confidence"],
  "properties": {
    "structure_type": {"type": "string", "enum": ["standalone", "subsidiary", "parent"]},
    "parent_company": {"type": ["string", "null"]},
    "is_pe_owned": {"type": "boolean"},
    "pe_owner": {"type": ["string", "null"]},
    "notable_sister_or_child_brands": {"type": "array", "items": {"type": "string"}},
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

## Worked example — Tableau (subsidiary)

```json
{
  "structure_type": "subsidiary",
  "parent_company": "Salesforce, Inc.",
  "is_pe_owned": false,
  "pe_owner": null,
  "notable_sister_or_child_brands": ["MuleSoft", "Slack"],
  "citations": [
    {"n": 1, "title": "sec.gov — Salesforce 10-K", "url": "https://www.sec.gov/..."}
  ],
  "sources": ["https://www.sec.gov/..."],
  "confidence": "high"
}
```

## Worked example — AlphaSense (parent, self-name)

```json
{
  "structure_type": "parent",
  "parent_company": "AlphaSense",
  "is_pe_owned": false,
  "pe_owner": null,
  "notable_sister_or_child_brands": ["Tegus"],
  "citations": [
    {"n": 1, "title": "alphasense.com — Tegus acquisition press release", "url": "https://www.alpha-sense.com/..."}
  ],
  "sources": ["https://www.alpha-sense.com/..."],
  "confidence": "high"
}
```

## Confidence rubric

- `high` — corroborating sources (filing, press release, Wikipedia).
- `medium` — one credible source; ownership recent or messy.
- `low` — only inference; mark and let writeback route to `needs_review`.

The orchestrator-side `arr-writeback` skill writes `parent_company` to the Notion `Parent` text property (applying the self-name rule from `structure_type`) and joins `notable_sister_or_child_brands` into the `sister/child` text property.
