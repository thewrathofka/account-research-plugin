---
name: arr-batch-lister
description: Lists all matching accounts from the Notion All Accounts CRM with full cursor pagination — bypasses the 100-result cap of the notion-query-database-view MCP tool. Uses Bash + curl directly against the Notion REST API. Required by /arr batch mode whenever the unresearched-account count may exceed 100.
allowed-tools: Bash
---

# arr-batch-lister — Paginated Account Lister

## Purpose

The MCP tool `notion-query-database-view` returns at most 100 results per call and does NOT expose `has_more` / `next_cursor` for pagination. For batch runs against an All Accounts CRM with more than 100 candidate accounts, this is a hard blocker — the 101st account simply never surfaces.

This skill paginates through the full Notion API result set using Bash + `curl` + cursor loops. Returns the COMPLETE list of accounts matching the requested filter, regardless of size.

This is the plugin's canonical way to resolve a batch account list. The orchestrator (`/arr`) calls this skill instead of `notion-query-database-view` whenever `--batch` mode is requested.

## One-time setup (REQUIRED before first batch run)

The skill uses Bash to call the Notion API directly with the shell env var `$NOTION_API_TOKEN`. That token belongs to the "Claude Code" Notion integration. By default, Notion integrations have NO access to any database until you grant it.

In the Notion UI:
1. Open the **All Accounts** database (DB ID `6d510b5a-9c8f-490f-8600-429184341edc`).
2. Click the `⋯` menu → **Connections** → search for **"Claude Code"** → **Add**.
3. (Optional) Repeat for any other databases the plugin should be able to query.

After granting access, this skill can paginate the database without any further setup.

If the token is unavailable or access is missing, this skill returns a structured error and the orchestrator falls back to `notion-query-database-view` with the "Unresearched Priority B" Notion view (capped at 100 but viable for small batches).

## Inputs

The orchestrator passes:
- `rep` — Rep select value (e.g. `"Katarina"`)
- `priority_type` — Priority Type select value (e.g. `"Priority B"`)
- `unresearched_only` — boolean (default true) — when true, adds `Last Researched is_empty` to the filter
- `since_days` — optional int — when set AND `unresearched_only=false`, adds `Last Researched on_or_before <today - N days>` to the filter
- `max` — optional int cap on total results returned
- `database_id` — Notion DB UUID (default `6d510b5a9c8f490f8600429184341edc`)
- `data_source_id` — optional Notion data source UUID (default `34b43129a67945e2940ec5b165e128be`); set to override the default data source within a multi-source database. **Note:** the Notion API generally queries by `database_id`; `data_source_id` is reserved here for future use if Notion's API exposes a per-data-source query endpoint.

## Pagination algorithm

```
results = []
cursor = null
loop:
    response = POST /v1/databases/{database_id}/query
        with body: {filter, sorts: [{property:"Account Name", direction:"ascending"}],
                    page_size: 100, start_cursor: cursor (if present)}
    results.extend(response.results)
    if max set AND len(results) >= max: trim and break
    if not response.has_more: break
    cursor = response.next_cursor
return results
```

## Filter shape

For the default case (unresearched Priority B for Katarina):

```json
{
  "and": [
    {"property": "Rep", "select": {"equals": "Katarina"}},
    {"property": "Priority Type", "select": {"equals": "Priority B"}},
    {"property": "Last Researched", "date": {"is_empty": true}}
  ]
}
```

When `unresearched_only=false` AND `since_days` is set:

```json
{
  "and": [
    {"property": "Rep", "select": {"equals": "Katarina"}},
    {"property": "Priority Type", "select": {"equals": "Priority B"}},
    {"or": [
      {"property": "Last Researched", "date": {"is_empty": true}},
      {"property": "Last Researched", "date": {"on_or_before": "<today - N days, ISO date>"}}
    ]}
  ]
}
```

## Implementation (Bash + curl + python3 for JSON handling)

```bash
#!/usr/bin/env bash
# Usage: arr-batch-lister <rep> <priority_type> <unresearched_only:true|false> [max] [since_days]
# Reads $NOTION_API_TOKEN from environment.

set -euo pipefail

REP="${1:-Katarina}"
PRIORITY="${2:-Priority B}"
UNRESEARCHED_ONLY="${3:-true}"
MAX="${4:-}"
SINCE_DAYS="${5:-}"

DB_ID="6d510b5a9c8f490f8600429184341edc"

if [[ -z "${NOTION_API_TOKEN:-}" ]]; then
  echo '{"error": "NOTION_API_TOKEN env var not set. Add it to ~/.zshrc or run inside a shell that has it."}' >&2
  exit 1
fi

# Build filter via python3 (JSON safety > shell quoting hell)
FILTER_JSON=$(python3 - "$REP" "$PRIORITY" "$UNRESEARCHED_ONLY" "${SINCE_DAYS:-}" <<'PY'
import json, sys, datetime
rep, prio, unres_only, since = sys.argv[1], sys.argv[2], sys.argv[3].lower() == "true", sys.argv[4]
ands = [
    {"property": "Rep", "select": {"equals": rep}},
    {"property": "Priority Type", "select": {"equals": prio}},
]
if unres_only:
    ands.append({"property": "Last Researched", "date": {"is_empty": True}})
elif since and since.isdigit():
    cutoff = (datetime.date.today() - datetime.timedelta(days=int(since))).isoformat()
    ands.append({"or": [
        {"property": "Last Researched", "date": {"is_empty": True}},
        {"property": "Last Researched", "date": {"on_or_before": cutoff}},
    ]})
print(json.dumps({"and": ands}))
PY
)

CURSOR=""
PAGE=0
ALL_RESULTS_FILE=$(mktemp)
echo "[]" > "$ALL_RESULTS_FILE"

while true; do
  PAGE=$((PAGE + 1))
  BODY=$(python3 - "$FILTER_JSON" "$CURSOR" <<'PY'
import json, sys
filt = json.loads(sys.argv[1])
cursor = sys.argv[2] if sys.argv[2] else None
body = {"filter": filt, "page_size": 100,
        "sorts": [{"property": "Account Name", "direction": "ascending"}]}
if cursor:
    body["start_cursor"] = cursor
print(json.dumps(body))
PY
  )

  RESPONSE=$(curl -s -X POST "https://api.notion.com/v1/databases/$DB_ID/query" \
    -H "Authorization: Bearer $NOTION_API_TOKEN" \
    -H "Notion-Version: 2022-06-28" \
    -H "Content-Type: application/json" \
    --data "$BODY")

  # Detect API error
  IS_ERROR=$(echo "$RESPONSE" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('object')=='error')")
  if [[ "$IS_ERROR" == "True" ]]; then
    echo "$RESPONSE" >&2
    rm -f "$ALL_RESULTS_FILE"
    exit 2
  fi

  # Merge results
  python3 - "$ALL_RESULTS_FILE" "$RESPONSE" <<'PY'
import json, sys
fp = sys.argv[1]
with open(fp) as f: acc = json.load(f)
new = json.loads(sys.argv[2])
acc.extend(new.get("results", []))
with open(fp, "w") as f: json.dump(acc, f)
PY

  HAS_MORE=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('has_more', False))")
  NEXT=$(echo "$RESPONSE" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('next_cursor') or '')")

  # Apply max cap
  if [[ -n "$MAX" ]]; then
    COUNT=$(python3 -c "import json; print(len(json.load(open('$ALL_RESULTS_FILE'))))")
    if [[ "$COUNT" -ge "$MAX" ]]; then
      python3 - "$ALL_RESULTS_FILE" "$MAX" <<'PY'
import json, sys
fp, mx = sys.argv[1], int(sys.argv[2])
with open(fp) as f: a = json.load(f)
with open(fp, "w") as f: json.dump(a[:mx], f)
PY
      break
    fi
  fi

  if [[ "$HAS_MORE" != "True" ]]; then break; fi
  CURSOR="$NEXT"
done

# Emit slim per-account JSON
python3 - "$ALL_RESULTS_FILE" <<'PY'
import json, sys
fp = sys.argv[1]
with open(fp) as f: pages = json.load(f)
out = []
for p in pages:
    props = p.get("properties", {})
    name = ""
    if (t := props.get("Account Name", {}).get("title")):
        name = t[0].get("plain_text", "")
    last = ""
    if (d := props.get("Last Researched", {}).get("date")):
        last = d.get("start", "")
    out.append({
        "page_id": p["id"],
        "account_name": name,
        "last_researched": last,
        "url": p.get("url", "")
    })
print(json.dumps({"count": len(out), "results": out}))
PY

rm -f "$ALL_RESULTS_FILE"
```

## Output JSON

```json
{
  "count": 47,
  "results": [
    {
      "page_id": "3523435e-7148-81f9-893e-c69289f229af",
      "account_name": "Colony Brands, Inc.",
      "last_researched": "",
      "url": "https://www.notion.so/3523435e714881f9893ec69289f229af"
    },
    {
      "page_id": "...",
      "account_name": "...",
      "last_researched": "",
      "url": "..."
    }
  ]
}
```

## Error responses

If `$NOTION_API_TOKEN` is missing:
```json
{"error": "NOTION_API_TOKEN env var not set. Add it to ~/.zshrc or run inside a shell that has it."}
```

If the integration doesn't have DB access (404 from Notion):
```json
{"object": "error", "status": 404, "code": "object_not_found", "message": "Could not find database with ID: ... Make sure the relevant pages and databases are shared with your integration \"Claude Code\".", ...}
```

On 404 from the API, the orchestrator should:
1. Print a one-line setup reminder: "Share the All Accounts DB with the Claude Code integration in Notion UI → Connections → Add."
2. Fall back to `notion-query-database-view` against the "Unresearched Priority B" view (capped at 100, but viable for small batches).

## How to invoke from the orchestrator

The `/arr` orchestrator invokes this skill in Step 1 of batch mode:

```
Use the Bash tool to run:

  bash ${CLAUDE_PLUGIN_ROOT}/skills/arr-batch-lister/list.sh \
    "<rep>" "<priority_type>" "<unresearched_only>" "<max>" "<since_days>"

Parse the JSON output. Use `results[*].page_id` and `results[*].account_name`
as the per-account loop inputs.
```

(The orchestrator may also choose to inline the Bash directly — but a standalone `list.sh` script in this skill's directory keeps the logic atomic and testable.)

## Hard rules

- **Always paginate to completion** OR until the `max` cap is hit. Never silently truncate at 100.
- **Sort by Account Name ascending** for deterministic ordering across runs.
- **Read-only** — this skill must NEVER write to Notion. Account list returned, period.
- **No external dependencies** — `bash`, `curl`, `python3` only. All three are available on Kali's macOS by default.
- **Error visibility** — surface 401/403/404 responses verbatim to stderr; the orchestrator decides whether to fall back or fail.

## Comparison: this skill vs. `notion-query-database-view` MCP tool

| Aspect | This skill (Bash + curl) | `notion-query-database-view` MCP |
|---|---|---|
| Pagination | Full — cursor loop to `has_more=false` | Capped at 100 results |
| Setup | Share DB with Claude Code integration once | None — uses session auth |
| Filter override | Full Notion API filter syntax | None — locked to view's pre-defined filter |
| Sort override | Yes (Account Name ASC fixed) | None — locked to view's sort |
| Cost | Free (no LLM tokens) | Free |
| Speed | ~200ms per 100-page round-trip | Similar |
| Auth surface | Shell env var `$NOTION_API_TOKEN` | Inherited from MCP session |
| Fallback recommendation | If 404, use the MCP path with "Unresearched" view | If >100 results expected, use this skill |

The plugin uses this skill by default for batch mode. The MCP path stays available as fallback when DB access isn't granted to the integration yet.
