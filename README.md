# account-research-plugin

Local Claude Code marketplace hosting the **`account-research`** plugin.

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

## What it does

11-module B2B account research pipeline for the Notion All Accounts CRM. Native Claude Code orchestration: `/arr` slash command → parallel module subagents → unified Notion writeback. Mirrors the output contract of the Python source-of-truth at `~/code/account-research-agent/`.

Full documentation: [`plugins/account-research/README.md`](plugins/account-research/README.md).

## Structure

```
account-research-plugin/                ← THIS DIR (a marketplace)
├── .claude-plugin/
│   └── marketplace.json                ← marketplace manifest
├── README.md                           ← marketplace readme (this file)
└── plugins/
    └── account-research/               ← THE PLUGIN
        ├── .claude-plugin/
        │   └── plugin.json
        ├── README.md                   ← plugin readme (full agent diagram, tool matrix)
        ├── commands/arr.md
        ├── skills/
        │   ├── arr-disambiguator/
        │   ├── arr-format-verifier/
        │   ├── arr-module-01-gate/
        │   ├── arr-module-02-revenue/
        │   ├── arr-module-03-pain-points/
        │   ├── arr-module-04-corporate/
        │   ├── arr-module-05-structural-news/
        │   ├── arr-module-06-triggers/
        │   ├── arr-module-07-creative/
        │   ├── arr-module-08-ads/
        │   ├── arr-module-09-competitors/
        │   ├── arr-module-10-industry/
        │   ├── arr-module-11-hiring/
        │   ├── arr-page-assembly/
        │   └── arr-writeback/
        └── tests/smoke-test.md
```

## Updating the plugin

Edit files under `plugins/account-research/` and commit. Claude Code re-reads the plugin from the local path on next reload (`/plugin update account-research@account-research-local` or restart).

## License

Solo project, public for visibility. No external contributions accepted.
