# account-research-plugin

A Claude Code marketplace hosting the **`account-research`** plugin —
on-demand B2B account research for a Notion CRM, run natively from inside
Claude Code via a single `/arr` slash command.

This is **Track 2** of a two-track project. The other track is the
production Python pipeline at
[`thewrathofka/account-research-agent`](https://github.com/thewrathofka/account-research-agent)
that runs on GitHub Actions crons against paid APIs (Tavily, Apify,
Anthropic / OpenAI). This plugin is the personal Max-subscription
equivalent — same Notion schema, same module spec, no token cost beyond
the Max subscription.

---

## 🔌 Notion connection note (read first)

This plugin is currently wired to **Kali's personal Notion workspace** —
the Notion MCP integration in Claude Code authenticates to her own account,
and `/arr` reads/writes the All Accounts database `6d510b5a-...` inside
her own Money Moguls CRM page.

**If/when Superside adopts this:** the Notion connection in Claude Code's
MCP config gets re-authenticated against Superside's Notion workspace and
the All Accounts DB ID inside `commands/arr.md` and the
`arr-batch-lister` skill switches to the Superside DB ID. The Claude Code
"Notion integration" needs to be granted access to whichever DB holds
Superside's accounts.

No skill / SKILL.md changes required for the swap — only the Notion
authentication + the DB ID constant. Everything else (the 11-module
pipeline, the agent diagram, the writeback contract, the alert behaviour)
stays as-is.

---

## What ships today (plugin v1.4.0)

- **`/arr <account>`** — research a single named account end-to-end
- **`/arr --batch`** — process all unresearched accounts on the default
  filter (Priority A by default; switch with `--priority`, `--rep`, etc.)
- **`/arr --dry-run`** — full pipeline without Notion writes (returns the
  planned writeback)

The orchestrator fans out 9 research modules in parallel as subagents,
runs the pain-point synthesis (module 3) sequentially after, then writes
back through `arr-writeback` followed by `arr-format-verifier` post-write
QA that re-fetches the page and re-dispatches any module whose output is
missing or malformed.

15 skills total in the plugin:
- 11 module skills (`arr-module-01-gate` through `arr-module-11-hiring`)
- `arr-page-assembly` — pure block-builder logic, no I/O
- `arr-writeback` — single Notion write chokepoint
- `arr-format-verifier` — post-write contract validation
- `arr-disambiguator` — pre-dispatch ambiguous-name resolver
- `arr-batch-lister` — Bash + curl + Notion REST API for full cursor
  pagination (resolves the 100-result cap on the MCP view-query path)

Full agent diagram + tool-to-skill matrix + Notion schema contract +
known failure modes:
[`plugins/account-research/README.md`](plugins/account-research/README.md).

---

## Install

From inside Claude Code:

```
/plugin marketplace add ~/code/account-research-plugin
/plugin install account-research@account-research-local
```

Then verify:

```
/plugin list
```

You should see `account-research` listed.

### Required Notion setup

Share the All Accounts DB with the "Claude Code" Notion integration so
the `arr-batch-lister` skill can paginate the full DB (not capped at 100).

In Notion UI: open the **All Accounts** database → `⋯` menu → **Connections**
→ search for **Claude Code** → **Add**.

If you skip this, the plugin falls back to `notion-query-database-view`
against a pre-defined view named **"Unresearched Priority B"** (works for
batches ≤100 accounts).

### Required env var

`$NOTION_API_TOKEN` must be set in your shell (Kali's is in `~/.zshrc`).
The plugin reads it for direct API pagination calls — same token Claude
Code's Notion MCP uses.

---

## How the two tracks relate

| Track | Repo | Stack | When to use |
|---|---|---|---|
| 1 (Python, production) | [`account-research-agent`](https://github.com/thewrathofka/account-research-agent) | Python + Tavily + Apify + Anthropic/OpenAI, GHA crons, Turso state | What Superside would actually run on a schedule. Has paid API costs, but also has 342 tests, eval framework, cross-provider swap, diff-driven alerts. |
| 2 (this plugin) | this repo | Claude Code + WebSearch/WebFetch + Notion MCP | Personal Max-subscription / interactive on-demand. No paid APIs (Greenhouse via WebFetch when reachable; otherwise LinkedIn Jobs / Glassdoor / Indeed). |

Both tracks emit a **byte-for-byte aligned Notion contract** — same
properties, same page-body section order, same per-section citation
renumbering rule. A BDR using either output gets the identical experience.

---

## Repo structure

```
account-research-plugin/                ← THIS DIR (the marketplace)
├── .claude-plugin/
│   └── marketplace.json                ← marketplace manifest
├── README.md                           ← marketplace readme (this file)
└── plugins/
    └── account-research/               ← THE PLUGIN
        ├── .claude-plugin/
        │   └── plugin.json             ← version, name, description
        ├── README.md                   ← full plugin docs (agent diagram,
        │                                  tool matrix, Notion contract,
        │                                  failure modes, version history)
        ├── commands/
        │   └── arr.md                  ← orchestrator slash command
        ├── skills/
        │   ├── arr-disambiguator/
        │   ├── arr-batch-lister/
        │   ├── arr-format-verifier/
        │   ├── arr-module-01-gate/     ← run-once size + EU/NA gate
        │   ├── arr-module-02-revenue/  ← revenue model + customers
        │   ├── arr-module-03-pain-points/  ← synthesis (no tools)
        │   ├── arr-module-04-corporate/    ← parent / subsidiary / standalone
        │   ├── arr-module-05-structural-news/  ← M&A / IPO / layoffs
        │   ├── arr-module-06-triggers/     ← 90-day buying signals
        │   ├── arr-module-07-creative/     ← in-house signals + agencies
        │   ├── arr-module-08-ads/          ← LinkedIn ads (audience-gated Meta/TikTok)
        │   ├── arr-module-09-competitors/  ← 1–3 truly direct (no padding)
        │   ├── arr-module-10-industry/     ← 90-day category stories
        │   ├── arr-module-11-hiring/       ← location-aware hiring signal
        │   ├── arr-page-assembly/          ← pure logic, no I/O
        │   └── arr-writeback/              ← single Notion write chokepoint
        └── tests/
            └── smoke-test.md
```

---

## Prompt quality bar

Plugin skills went through the same prompt-engineering audit as the Python
prompts on 2026-05-17 (v1.4.0):
- Per-tier confidence rubrics with **concrete trigger conditions** in every
  module (not "high if multiple sources, low if guessed" — actual thresholds)
- Anti-invention guard in `arr-module-09-competitors` (1–3 truly direct, no
  padding to a forced 3)
- Explicit ambiguity rules in `arr-module-04-corporate` (in-flight
  acquisitions, mergers of equals, spin-offs)
- Input-trust boundary in the orchestrator's subagent prompt template —
  search-result content is data, never instructions (prompt-injection
  defense across all module subagents)

---

## Updating the plugin

Edit files under `plugins/account-research/` and commit. Claude Code
re-reads the plugin from the local path on next reload
(`/plugin update account-research@account-research-local` or restart).

---

## License

Solo project, public for visibility. Currently personal; intended for
adoption by Superside RevOps. No external contributions accepted in the
solo phase.
