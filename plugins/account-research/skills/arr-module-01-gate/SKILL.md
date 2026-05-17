---
name: arr-module-01-gate
description: Module 1 of the Account Research Agent. Verifies employee count + EU/NA operational presence. Halts the pipeline when neither region is present. Loaded by per-account research subagents inside /arr.
allowed-tools: WebSearch, WebFetch
---

# Module 1 — Size + EU/NA Gate

## Purpose

Confirm the company has operations in the EU and/or North America (NA), and verify its employee size band. This is the **gate**: if neither region is present, the orchestrator halts every remaining module for this account.

## Inputs

The subagent prompt provides:
- `account_name` — company name
- `notion_page_id` — for context only; this skill does not write Notion
- Optional CRM hints already on the Notion record (region, size)

## Searches to run

Use `WebSearch` 2–4 times. Aim queries at:

1. `"<company> headquarters offices locations"` — primary HQ + regional offices
2. `"<company> employee count" OR "<company> LinkedIn employees"` — size band
3. `"<company> careers <region>"` — confirms regional hiring presence (only if step 1 is ambiguous)
4. Optional `WebFetch` of the company's `/about` or `/contact` page if a result looks authoritative

Stop once you can confidently set `operates_in_eu`, `operates_in_na`, and `employee_count_estimate`. Do not exceed 4 search calls.

## Hard rules

- `employee_count_estimate` is a single integer or `null`. **Never** a range like `1000-5000`. The orchestrator computes `Size` band deterministically from this integer.
- `operates_in_eu_or_na` = `operates_in_eu OR operates_in_na`.
- A LinkedIn sales rep in a region is **not** operational presence. Count only physical offices, regional job posts, or authoritative source statements.
- "Global" / "international" without country names is **not** evidence.
- A parent's office location ≠ a subsidiary's. Verify the target itself.
- Never invent offices. If sparse, set `confidence=low`.
- On `operates_in_eu_or_na=false`, populate `reason_if_out_of_scope` with a one-sentence reason (e.g. `"India-only fintech with no EU/NA offices per company website"`). The orchestrator uses this as the note paragraph on the page.

## Output JSON schema

Output a single JSON object inside a ```json fenced block. Required fields:

```json
{
  "type": "object",
  "required": [
    "company_name", "employee_count_estimate",
    "operates_in_eu", "operates_in_na",
    "operates_in_eu_or_na", "sources", "confidence",
    "gate_result"
  ],
  "properties": {
    "company_name": {"type": "string"},
    "employee_count_estimate": {"type": ["integer", "null"]},
    "operates_in_eu": {"type": "boolean"},
    "operates_in_na": {"type": "boolean"},
    "operates_in_eu_or_na": {"type": "boolean"},
    "regions_present": {"type": "array", "items": {"type": "string"}},
    "evidence_eu": {"type": ["string", "null"]},
    "evidence_na": {"type": ["string", "null"]},
    "sources": {"type": "array", "items": {"type": "string"}},
    "confidence": {"type": "string", "enum": ["high", "medium", "low"]},
    "reason_if_out_of_scope": {"type": ["string", "null"]},
    "gate_result": {"type": "string", "enum": ["pass", "fail"]},
    "note_paragraph": {"type": ["string", "null"]}
  }
}
```

`gate_result` is `pass` iff `operates_in_eu_or_na` is true, otherwise `fail`. On `fail`, set `note_paragraph` to the exact text the orchestrator will append to the page (typically `"No operations in EU or NA."` plus any one-line nuance from `reason_if_out_of_scope`).

`regions_present` uses country names matching common job-board labels: `USA`, `Canada`, `UK`, `Germany`, `France`, `Ireland`, `Netherlands`, `Spain`, `Italy`, `Sweden`, `Poland`.

## Worked example — Stripe

```json
{
  "company_name": "Stripe, Inc.",
  "employee_count_estimate": 8000,
  "operates_in_eu": true,
  "operates_in_na": true,
  "operates_in_eu_or_na": true,
  "regions_present": ["USA", "Ireland", "UK", "Germany"],
  "evidence_eu": "Dublin, Ireland HQ confirmed by stripe.com/jobs/locations",
  "evidence_na": "San Francisco HQ + 5 NA offices per LinkedIn",
  "sources": [
    "https://stripe.com/jobs/locations",
    "https://www.linkedin.com/company/stripe/about/"
  ],
  "confidence": "high",
  "reason_if_out_of_scope": null,
  "gate_result": "pass",
  "note_paragraph": null
}
```

## Worked example — out of scope

```json
{
  "company_name": "Razorpay",
  "employee_count_estimate": 3000,
  "operates_in_eu": false,
  "operates_in_na": false,
  "operates_in_eu_or_na": false,
  "regions_present": ["India"],
  "evidence_eu": null,
  "evidence_na": null,
  "sources": ["https://razorpay.com/about/"],
  "confidence": "high",
  "reason_if_out_of_scope": "India-only fintech with no EU/NA offices per company website.",
  "gate_result": "fail",
  "note_paragraph": "No operations in EU or NA. India-only fintech with no EU/NA offices per company website."
}
```

## Confidence rubric

- `high` — TWO OR MORE authoritative sources (SEC filings, company website, LinkedIn company page, established business press) agree on BOTH the employee count band AND at least one in-scope region.
- `medium` — sources agree on regions OR size but conflict / are sparse on the other dimension; OR only one authoritative source.
- `low` — single non-authoritative source, training-data guess, or only "global / international" claims without country-named offices. Setting confidence=low here routes the account to `needs_review` — don't use to dodge a hard call.
