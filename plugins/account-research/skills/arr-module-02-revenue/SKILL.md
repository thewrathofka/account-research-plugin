---
name: arr-module-02-revenue
description: Module 2 of the Account Research Agent. Researches how the company makes money — revenue model, primary customer segment, primary products — and produces the Overview paragraph text with [N] citation markers. Loaded by per-account research subagents inside /arr.
allowed-tools: WebSearch, WebFetch
---

# Module 2 — Revenue Model + Customers + Products

## Purpose

Produce the **Overview** paragraph on the page body: a 2–3 sentence summary of revenue model + primary customer segment + primary products, with `[N]` citation markers after specific factual claims.

## Inputs

- `account_name`
- Optional context from module 1 (regions, employee count)

## Searches to run

Use `WebSearch` 2–4 times. Decompose the question — ask separately for each pillar to avoid mush.

1. `"<company> revenue model"` or `"<company> how they make money"`
2. `"<company> pricing"` or `"<company> customers" OR "<company> case studies"`
3. `"<company> products"` (skip if the first two already returned a product list)
4. Optional `WebFetch` of the company's `/pricing` or product page if a search result looks authoritative

## Hard rules

- `summary` is 2–3 sentences written for a sales-team audience. Place `[N]` markers immediately after specific factual claims (revenue numbers, product names, segment names).
- `revenue_model` uses business terms: `Subscription`, `Transaction`, `Marketplace`, `Advertising`, `Hardware`, `Services`, `Hybrid`. Combine with `+` if needed (e.g. `Subscription SaaS (per-seat) + usage-based add-ons`).
- Do NOT speculate beyond the sources. If the company is private and the model is unclear, write `"Unclear from public sources"` and set `confidence=low`.
- `primary_products` is a short list (1–5 named SKUs / product lines).
- Citation rules: `[N]` markers must be contiguous (1, 2, 3, …), every `url` must come from a tool result this run, never invent URLs.

## Output JSON schema

```json
{
  "type": "object",
  "required": ["revenue_model", "primary_customer_segment", "primary_products",
               "summary", "citations", "sources", "confidence"],
  "properties": {
    "revenue_model": {"type": "string"},
    "primary_customer_segment": {"type": "string"},
    "primary_products": {"type": "array", "items": {"type": "string"}},
    "summary": {"type": "string"},
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

`sources` should equal the de-duplicated set of `citations[].url`.

## Worked example — Slack

```json
{
  "revenue_model": "Subscription SaaS (per-seat) + usage-based add-ons",
  "primary_customer_segment": "Mid-market and enterprise B2B SaaS companies",
  "primary_products": ["Slack core platform", "Slack Connect", "Slack AI"],
  "summary": "Slack monetizes via per-seat subscriptions to its enterprise collaboration platform [1], primarily serving mid-market and enterprise B2B software companies [2]. Add-ons include Slack Connect for cross-org collaboration and Slack AI for enterprise-grade AI features [3].",
  "citations": [
    {"n": 1, "title": "slack.com — pricing", "url": "https://slack.com/pricing"},
    {"n": 2, "title": "salesforce.com — Slack customers", "url": "https://www.salesforce.com/news/..."},
    {"n": 3, "title": "slack.com — Slack AI launch", "url": "https://slack.com/blog/news/slack-ai"}
  ],
  "sources": [
    "https://slack.com/pricing",
    "https://www.salesforce.com/news/...",
    "https://slack.com/blog/news/slack-ai"
  ],
  "confidence": "high"
}
```

## Confidence rubric

- `high` — revenue model explicitly stated in earnings reports, investor pages, pricing pages, or major business-press coverage; primary products and customer segment both confirmed by primary sources.
- `medium` — revenue model inferred from product/customer pattern (SaaS playbook, marketplace economics); some products listed but list may be incomplete.
- `low` — private company with no public revenue disclosure; model assumed from category convention rather than confirmed.

The orchestrator-side `arr-writeback` skill renders `summary` as the **Overview** paragraph, rewriting `[N]` markers into inline Notion `rich_text` link spans.
