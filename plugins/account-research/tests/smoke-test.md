# Smoke Test — `/arr`

Run this after every plugin version bump, after any change to `arr.md` / `arr-writeback` / `arr-format-verifier`, and before kicking off the next batch.

---

## Pre-flight

1. **Verify Notion view exists.** The "Unresearched Priority B" view must exist in the All Accounts database with filter `Rep + Priority Type + Last Researched is empty`. Without it, batch mode silently truncates at 100 results.

2. **Verify plugin loaded.** In Claude Code:
   ```
   /plugin list
   ```
   You should see `account-research` listed.

3. **Verify schema alignment.** Diff the schema enums in `~/code/account-research-plugin/skills/arr-writeback/SKILL.md` against `~/code/account-research-agent/crm.py` (lines 52–84). Every option string should appear verbatim in both.

---

## Smoke test — single account

Pick an account with a known parent structure to exercise module 5. Good candidates: **AlphaSense** (parent-with-children), **Tableau** (subsidiary of Salesforce), or any of the 4 normalization candidates from the May 2026 batch (Trane Technologies / N26 / Related Companies / YASH Technologies — re-running fully through the new pipeline rebuilds them in canonical form).

```
/arr Tableau --dry-run
```

Dry-run prints the planned writeback. Inspect the printed payload and check:

- All required properties present: `Size`, `Buying Signals`, `Pain Point Tags`, `Structure Notes`, `sister/child`, `Parent`, `Last Researched`, `Research Confidence`, `Research Status`.
- `Buying Signals` and `Pain Point Tags` values are from the canonical vocabularies.
- `Research Status ∈ {done, needs_review, failed, out_of_scope}` (NOT `Qualified` / `Prospecting` / `SQL` / `SAL` / `Neglected`).
- `Prospecting Status` is NOT in the property payload (the verifier will flag if it is).
- Page-body blocks start with `## Research — <date>` (no `# H1`).
- Section names are from the canonical list: `Overview`, `Possible Pain Points`, `News`, `Creative Posture`, `Competitor Landscape` (heading_2); `Headcount`, `Ads Running`, per-signal subheadings (heading_3).

If dry-run looks correct, run for real:

```
/arr Tableau
```

The orchestrator will:
1. Skip disambiguator (Tableau isn't ambiguous).
2. Run module 1 gate (Tableau passes — multinational presence).
3. Fan out 9 module subagents in parallel.
4. Run module 3 synthesis.
5. Assemble blocks via `arr-page-assembly`.
6. Write via `arr-writeback`.
7. **Verify via `arr-format-verifier`**.

The summary line should read:
```
Tableau: status=done conf=<high|medium> (wrote, verified)
```

---

## 7 acceptance criteria

After the smoke test completes, fetch the page via `notion-fetch` (or use the orchestrator's verifier output) and confirm:

### 1. Properties writeback
`date:Last Researched:start`, `Research Confidence`, `Research Status` are ALL non-empty. (Catches Failure A — properties skipped despite body landing.)

### 2. Body format
Page contains `## Research — <today's date>` at the top. Every block under it is `heading_2`, `heading_3`, `paragraph`, or `bulleted_list_item`. No `heading_1`. Section names exactly match the canonical 7 (Overview, Possible Pain Points, News, Creative Posture, Competitor Landscape) plus subsections (Headcount, Ads Running, per-signal). (Catches Failure B — non-canonical sections.)

### 3. Status field
`Research Status ∈ {done, needs_review, failed, out_of_scope}`. `Prospecting Status` is unchanged from its pre-run value (snapshot before running and compare after). (Catches Failure C — agent touching BDR-managed fields.)

### 4. Parent/sister logic
If the smoke-test account is a subsidiary (e.g. Tableau), `Parent` holds the parent name (`Salesforce, Inc.`) and `sister/child` holds siblings (`MuleSoft, Slack`). If it's a standalone-parent (e.g. AlphaSense), `Parent` holds its own name and `sister/child` holds children (`Tegus`). If neither, both empty. (Catches Failure D — Parent/sister swap.)

### 5. Pain Point Tags
≥1 value set, all from the canonical 10-tag vocabulary. Body's `### Possible Pain Points` section uses the v3.0 bullet structure: intro paragraph + per-pain bullets (`**label** — body`) + final `- Pain tags:` bullet.

### 6. Tag destination
Any tags written by modules 7/13/14 are in `Buying Signals`, NOT `Buying Intent`. `Buying Intent` is unchanged from pre-run state. (Catches the source-of-truth drift from the legacy `~/.claude/commands/research-account.md` spec.)

### 7. Format-verifier ran
The orchestrator's summary line includes `(wrote, verified)`. If you see `VERIFIER FAILED:` instead, that's a fail — read the diagnostic, fix the cause, re-run.

---

## Escalation: 5-account batch

If single-account smoke passes:

```
/arr --batch --max 5
```

Spot-check all 7 criteria on each of the 5 accounts. If all pass, the plugin is verified for the full batch.

---

## Failure-mode coverage check

Each criterion above maps to a failure mode observed in the May 2026 batch run (see README.md "Failure modes encoded into the plugin"):

| Smoke criterion | Catches failure mode |
|---|---|
| 1 | A — Properties writeback skipped |
| 2 | B — Body format drift |
| 3 | C — Wrote to Prospecting Status |
| 4 | D — Parent/sister swap |
| 5 | (Pain Point Tags presence — derived from module 3 v3.0 contract) |
| 6 | Source-of-truth drift (legacy spec said Buying Intent) |
| 7 | A+B+C+D in aggregate — verifier is the catch-all |

Failure modes E (stream timeouts), F (child-as-dupe), G (WebFetch denied), H (pagination), I (disambiguation) are mitigated structurally and don't have direct smoke-test criteria — they're either silently handled or documented as known limitations.

---

## Regression test — re-running a previously-broken account

For high-confidence sign-off, re-run one of the 4 May 2026 normalization candidates:

```
/arr "Trane Technologies"
```

Then compare to the prior state captured in `~/.claude/plans/let-s-think-of-a-graceful-tower.md` (Part 2, Failure A). The re-run should:
- Set `date:Last Researched:start = today` (was empty).
- Set `Research Confidence` (was empty).
- Set `Parent`, `sister/child`, `Structure Notes` (were empty).
- Rewrite body in canonical PMG structure (was `# H1` + custom `## H2`).

If all 7 acceptance criteria pass on Trane after re-running, the plugin has fully closed the regression.
