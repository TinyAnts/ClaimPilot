#!/bin/bash
# ClaimPilot orchestrator: one gated pass over the claims pipeline.
# Each LLM stage is verify-and-retried (<=5) until its input status clears; adjudication is deterministic code.
export PATH="$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
set -u
ABS="$HOME/openclaw-insurance/workspace"; CLAIMS="$ABS/data/claims.json"; AUD="$ABS/data/audit-log.jsonl"
[ -f "$CLAIMS" ] || echo '[]' > "$CLAIMS"; mkdir -p "$ABS/inbox" "$ABS/data/processed"
cnt(){ python3 -c "import json;d=json.load(open('$CLAIMS'));print(sum(1 for c in d if c.get('status')=='$1'))" 2>/dev/null||echo 0; }
inbox_n(){ ls -1 "$ABS/inbox" 2>/dev/null|wc -l; }
F="You MUST call your file tools this turn. A reply without an actual tool call and file write is a FAILURE. Do it now:"
stage(){ local a="$1" st="$2" m="$3"; [ "$(cnt "$st")" -gt 0 ]||return 0
  for t in 1 2 3 4 5; do echo "--- $a (try $t, $st=$(cnt "$st")) ---"; openclaw agent --agent "$a" --message "$F $m" >/dev/null 2>&1
    [ "$(cnt "$st")" -eq 0 ]&&{ echo "  cleared $st"; return 0; }; done; echo "  WARN: $a left $(cnt "$st") at $st"; }
if [ "$(inbox_n)" -gt 0 ]; then for t in 1 2 3 4 5; do echo "--- intake (try $t) ---"
  openclaw agent --agent intake --message "$F (1) for each .json in $ABS/inbox/, read it; (2) append to the JSON array at $CLAIMS an object with claim_id (CLM-YYYYMMDD-XXXX), source_file, external_id, status received; (3) write $CLAIMS; (4) move the file to $ABS/data/processed/; (5) append a line to $AUD. Reply ONLY: INTAKE claim_id." >/dev/null 2>&1
  [ "$(inbox_n)" -eq 0 ]&&{ echo "  inbox cleared"; break; }; done; fi
stage doc-extractor received "(1) read $CLAIMS; (2) for the claim with status received, read its source in $ABS/data/processed/ (named in source_file); (3) copy fields pet, policy_id, policy_start, claim_date, diagnosis, treatment, line_items, invoice_total; (4) set status extracted; (5) write $CLAIMS; (6) append a line to $AUD. Reply ONLY: EXTRACTED claim_id."
stage policy-matcher extracted "(1) read $ABS/policy/policy-rules.md and $ABS/policy/coverage-matrix.md; (2) read $CLAIMS; (3) for the claim with status extracted add policy_eval (peril, covered, waiting_ok, excluded_items, deductible, reimburse_pct); (4) set status policy_checked; (5) write $CLAIMS; (6) append a line to $AUD. Reply ONLY: POLICY claim_id."
[ "$(cnt policy_checked)" -gt 0 ]&&{ echo "--- medical-necessity ---"; openclaw agent --agent medical-necessity --message "$F (1) read $CLAIMS; (2) for the claim with status policy_checked add necessity (verdict, notes); (3) do NOT change status; (4) write $CLAIMS. Reply ONLY: NECESSITY claim_id." >/dev/null 2>&1; }
stage fraud-anomaly policy_checked "(1) read $CLAIMS; (2) for the claim with status policy_checked add risk (score 0-100, flags); (3) set status risk_scored; (4) write $CLAIMS; (5) append a line to $AUD. Reply ONLY: RISK claim_id."
# --- deterministic adjudication (closed-form; never an LLM) ---
[ "$(cnt risk_scored)" -gt 0 ]&&{ echo "--- adjudication (code) ---"; python3 - "$CLAIMS" "$AUD" <<'PY'
import json,sys,datetime
cp,ap=sys.argv[1],sys.argv[2]; ANNUAL=10000; d=json.load(open(cp)); ch=False
for c in d:
    if c.get('status')!='risk_scored': continue
    pe=c.get('policy_eval',{}) or {}
    if pe.get('covered') is None or pe.get('peril')=='unknown': c['recommendation']='RETURNED'; c['payout']=0.0
    elif pe.get('covered') is False or pe.get('waiting_ok') is False: c['recommendation']='DENY'; c['payout']=0.0
    else:
        excl=set(pe.get('excluded_items',[]) or []); ea=sum((i.get('amount',0) or 0) for i in c.get('line_items',[]) if i.get('desc') in excl)
        cov=(c.get('invoice_total',0) or 0)-ea; ded=pe.get('deductible',0) or 0; pct=(pe.get('reimburse_pct',0) or 0)/100.0
        raw=max(0,(cov-ded))*pct; c['payout']=round(min(raw,ANNUAL),2)
        c['recommendation']=('DENY' if cov<=0 else ('PARTIAL' if (excl or raw>ANNUAL) else 'APPROVE'))
    c['status']='adjudication_drafted'; ch=True
if ch: json.dump(d,open(cp,'w'),indent=2); open(ap,'a').write(json.dumps({'event':'adjudication_drafted','agent':'adjudication(code)','ts':datetime.datetime.now(datetime.timezone.utc).isoformat()})+'\n'); print('  adjudication written')
PY
}
stage notifier adjudication_drafted "(1) read $CLAIMS; (2) for the claim with status adjudication_drafted set status human_review; (3) write $CLAIMS. Reply ONLY: NOTIFIED claim_id."
echo "--- audit-logger ---"; openclaw agent --agent audit-logger --message "$F ensure $AUD has one line per status transition in $CLAIMS; append missing ones; do not change statuses. Reply ONLY: AUDIT done." >/dev/null 2>&1
echo "=== pass complete $(date -u +%FT%TZ) ==="
