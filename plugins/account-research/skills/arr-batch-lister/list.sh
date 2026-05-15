#!/usr/bin/env bash
# arr-batch-lister/list.sh
#
# Paginate the Notion All Accounts CRM via the REST API.
# Bypasses the 100-result cap of `notion-query-database-view` MCP tool.
#
# Usage:
#   ./list.sh <rep> <priority_type> <unresearched_only:true|false> [max] [since_days]
#
# Reads $NOTION_API_TOKEN from environment.
#
# Emits JSON to stdout:
#   {"count": N, "results": [{"page_id", "account_name", "last_researched", "url"}, ...]}
#
# Exit codes:
#   0 — success
#   1 — missing env var
#   2 — Notion API error (404/401/403 etc.) — full response on stderr

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
ALL_RESULTS_FILE=$(mktemp)
echo "[]" > "$ALL_RESULTS_FILE"
trap 'rm -f "$ALL_RESULTS_FILE"' EXIT

while true; do
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

  IS_ERROR=$(echo "$RESPONSE" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('object')=='error')" 2>/dev/null || echo "True")
  if [[ "$IS_ERROR" == "True" ]]; then
    echo "$RESPONSE" >&2
    exit 2
  fi

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

  if [[ -n "$MAX" ]]; then
    COUNT=$(python3 -c "import json; print(len(json.load(open('$ALL_RESULTS_FILE'))))")
    if (( COUNT >= MAX )); then
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
print(json.dumps({"count": len(out), "results": out}, indent=2))
PY
