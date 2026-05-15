---
name: arr-page-assembly
description: Pure-logic helper for /arr. Takes the 10 module JSON outputs and produces the ordered list of Notion block payloads with [N] markers replaced by inline rich_text link spans, deduped per section. No tools, no Notion calls. Used by arr-writeback.
---

# arr-page-assembly — Page Body Block Builder

## Purpose

Take the 10 module JSON outputs and emit the **ordered list of Notion block payloads** for the page body, with per-section citation renumbering and `[N]` markers rewritten into inline `rich_text` link spans.

This skill performs no I/O. It is logic-only. `arr-writeback` invokes it to compute the payload it will then pass to `notion-create-pages`.

## Inputs

A dictionary keyed by module name:
- `module_01_gate`
- `module_03_revenue_model`
- `module_04_pain_points`
- `module_05_corporate_structure`
- `module_06_structural_news`
- `module_07_trigger_events`
- `module_09_creative_reality`
- `module_10_ad_library`
- `module_12_competitor_snapshot`
- `module_13_industry_pulse`
- `module_14_hiring_signal`

Any of modules 3–14 may be `null` or `{"error": ...}` if its subagent failed — assembly must skip those sections rather than crash.

## Canonical page-body section order

Emit blocks in this order. Skip any section whose source module is missing/null.

1. **Overview** (heading_2) — from module 3 `summary`
2. **Headcount** (heading_3 nested intent, but Notion API treats it as a sibling block; emit as heading_3) — from module 14 `headcount_summary`
3. **Possible Pain Points** (heading_2) — from module 4 `intro` paragraph + one `bulleted_list_item` per `pain_points[i]` (rendered as `**{label}** — {body}`) + one final tag bullet `Tags: {comma-joined tags}`
4. **News** (heading_2) — module 7 trigger bullets, then per-signal subheadings as `heading_3` for each detected signal grouping (e.g. `### funding round` followed by its `trigger_details` bullet; `### industry movement` followed by module 13 stories that have `buying_implication="industry movement"`; `### hiring` / `### downsizing` from module 14 + module 6 if applicable)
5. **Creative Posture** (heading_2) — from module 9 `creative_posture_summary`
6. **Ads Running** (heading_3) — one `bulleted_list_item` per platform from module 10: `**{platform}** — {ads_running} active ({volume}). {note}`
7. **Competitor Landscape** (heading_2) — module 12 competitor bullets, then module 13 story bullets appended

Module 5's outputs go to Notion properties only (no page-body block here). Module 6's `event_summary` is rendered inline under the appropriate News subheading if present.

## Per-section citation renumbering

For each section that contains `[N]` markers, perform this pass:

1. Walk every module contributing to the section, in display order.
2. Collect citation entries from each contributing module: `{original_n, title, url, source_module}`.
3. **Dedupe by URL** — same URL across multiple modules collapses to one entry.
4. Renumber globally per section starting at 1.
5. Build a map `{(source_module, original_n) → new_n}`.
6. For each block's text, rewrite every `[N]` marker into an inline Notion `rich_text` segment of the form:

   ```json
   {
     "type": "text",
     "text": {"content": "[{new_n}]", "link": {"url": "<deduped_url>"}}
   }
   ```

7. **Do NOT emit a footnote `Sources:` bullet list per section** — the citation system was simplified 2026-05-12 to inline-only. Do NOT emit a global page-bottom `Sources` heading either.

## Rich text rewriting

For each block whose text contains `[N]` markers, split the text into a sequence of `rich_text` items:

- Plain prefix → `{"type": "text", "text": {"content": "..."}}`
- `[N]` token → `{"type": "text", "text": {"content": "[{new_n}]", "link": {"url": "..."}}}`
- Plain suffix → `{"type": "text", "text": {"content": "..."}}`

Continue until the marker iterator is exhausted, then append any remaining tail.

## Block type reference

Use these Notion block types:

- `heading_2` — top-level section headers (Overview, Possible Pain Points, News, Creative Posture, Competitor Landscape)
- `heading_3` — subsection headers (Headcount, Ads Running, per-signal subheadings under News)
- `paragraph` — narrative summaries (module 3, module 9, module 14 headcount, module 4 intro, module 6 event_summary)
- `bulleted_list_item` — pain bullets, trigger bullets, ad-platform bullets, competitor bullets, industry stories

Each block payload is:

```json
{
  "object": "block",
  "type": "heading_2",
  "heading_2": {"rich_text": [{"type": "text", "text": {"content": "Overview"}}]}
}
```

## Empty-section policy

- If a module is missing/null/errored → skip the section. Don't emit an empty heading.
- If module 7's `triggers_detected=[]` AND module 13's `stories=[]` AND module 14's signal is null AND module 6 produced no `event_summary` → omit the **News** heading entirely.
- If module 10's three platforms are all `ads_running=0` and all "not applicable" → emit the heading but with a single bullet `No active ad library presence detected.`

## Output

Return a tuple `(blocks, properties_hints)`:

- `blocks` — ordered list of Notion block payloads, ready to splat into `notion-create-pages`' children/content.
- `properties_hints` — a small object the caller (`arr-writeback`) uses to derive Notion properties (e.g. the final list of `Buying Signals` collected across modules 7+13+14 after citation/section assembly so the multi-select payload aligns with what's actually on the page). This is a convenience surface, not a contract — the property values still come from the module outputs directly.

## Worked example — collapsed citation pass for News section

Inputs (simplified):

```
module_07.trigger_details[0].summary = "Raised $50M Series C led by Sequoia [1]."
module_07.citations = [{"n": 1, "title": "tc.com — Series C", "url": "https://tc.com/x"}]

module_13.stories[0].headline = "Sector M&A spike in Q1 2026 [1]"
module_13.citations = [{"n": 1, "title": "rb.com — Q1 M&A spike", "url": "https://rb.com/y"}]
```

After renumbering per the News section (display order: module 7 → module 13):

```
[1] → "Raised $50M Series C led by Sequoia [1]." → https://tc.com/x
[2] → "Sector M&A spike in Q1 2026 [2]" → https://rb.com/y
```

If module 13 had cited `https://tc.com/x` (same URL as module 7), the dedupe collapses both `[N]` markers in that section into the same new `[1]`.

## Hard rules

- **Never** mutate the input module outputs. Build new objects.
- **Never** invent URLs. Citations only carry URLs that appear in `module_NN.citations[].url` or `module_NN.sources`.
- **Order matters.** Section order is the canonical order above. Per-signal News subheadings are emitted in this order: `funding round`, `active creative jobs`, `rebrand/campaign`, `agency switch`, `AI initiative`, `industry movement`, `hiring`, `downsizing`.
- **No emojis** in headings or bullets.
- **No global `Sources` heading.** The 2026-05-12 simplification removed both per-section `Sources:` footnotes and the page-bottom global `Sources` heading.

## How `arr-writeback` calls this

`arr-writeback` calls `arr-page-assembly` immediately after collecting all 10 module outputs and before calling `notion-update-page` + `notion-create-pages`. The returned `blocks` list goes directly into the create-pages payload; `properties_hints` is merged with property values derived from the raw module outputs.
