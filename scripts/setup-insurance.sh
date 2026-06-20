#!/bin/bash
# Create the project + state folders and empty data files. Idempotent. Run on the UDOO.
set -e
PROJ="$HOME/openclaw-insurance"
STATE="$HOME/.openclaw-insurance-state"
WS="$PROJ/workspace"

mkdir -p "$STATE"
mkdir -p "$WS"/{policy,data,inbox,samples}
for a in intake doc-extractor policy-matcher adjudication-drafter audit-logger notifier \
         medical-necessity fraud-anomaly pattern-review; do
  mkdir -p "$WS/agents/$a"
done

# create empty data files only if missing (never clobber live data)
[ -f "$WS/data/claims.json" ]      || echo '[]' > "$WS/data/claims.json"
[ -f "$WS/data/audit-log.jsonl" ]  || : > "$WS/data/audit-log.jsonl"
[ -f "$WS/data/patterns.json" ]    || echo '{}' > "$WS/data/patterns.json"

chmod 700 "$PROJ" "$STATE" 2>/dev/null || true
echo "Folders ready:"
echo "  project (dumpable): $PROJ"
echo "  state (never dump):  $STATE"
echo "Next: fill ~/openclaw-insurance/.env (Step 3), then validate (Step 4)."
