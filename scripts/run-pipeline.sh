#!/bin/bash
# ClaimPilot v2 orchestrator.
# Change vs v1: (a) explicit `returned` route for unusable documents,
# (b) LLM does ONLY judgement (field extraction + peril classification);
#     ALL deterministic policy logic (waiting period, exclusions, coverage) runs in code.
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

# 1. INTAKE (LLM)
if [ "$(inbox_n)" -gt 0 ]; then for t in 1 2 3 4 5; do echo "--- intake (try $t) ---"
  openclaw agent --agent intake --message "$F (1) for each .json in $ABS/inbox/, read it; (2) append to the JSON array at $CLAIMS an object with claim_id (CLM-YYYYMMDD-XXXX), source_file, external_id, status received; (3) write $CLAIMS; (4) move the file to $ABS/data/processed/; (5) append a line to $AUD. Reply ONLY: INTAKE claim_id." >/dev/null 2>&1
  [ "$(inbox_n)" -eq 0 ]&&{ echo "  inbox cleared"; break; }; done; fi

# 2. DOC-EXTRACTOR (LLM) — extraction + usability judgement -> extracted | returned
stage doc-extractor received "(1) read $CLAIMS; (2) for the claim with status received, read its source in $ABS/data/processed/ (named in source_file); (3) copy fields pet, policy_id, policy_start, claim_date, addons, diagnosis, treatment, line_items, invoice_total into the claim; (4) IF the diagnosis field is empty, missing, or unreadable, set status to returned and set return_reason to missing or illegible diagnosis; OTHERWISE set status to extracted; (5) write $CLAIMS; (6) append a line to $AUD. Reply ONLY: DOC claim_id status."

# 3. POLICY-MATCHER (LLM) — JUDGEMENT ONLY: classify peril + flag pre-existing
stage policy-matcher extracted "(1) read $CLAIMS; (2) for the claim with status extracted, read its diagnosis and treatment; (3) classify peril as EXACTLY ONE of: accident, illness, orthopedic, cosmetic, wellness. Use accident for trauma/foreign body/laceration/fracture; orthopedic for cruciate, patella, hip dysplasia; cosmetic for elective ear crop, declaw, cosmetic dental; wellness for routine exam, vaccination, heartworm prevention; illness otherwise. (4) set preexisting_suspected true only if the record clearly indicates the condition predates the policy start, else false; (5) write both fields into the claim and set status to classified; (6) write $CLAIMS. Do NOT compute dates, exclusions, deductibles or coverage. Reply ONLY: PERIL claim_id peril."

# 4. POLICY ENGINE (CODE) — all deterministic policy logic
if [ "$(cnt classified)" -gt 0 ]; then echo "--- policy engine (code) ---"; python3 - "$CLAIMS" "$AUD" <<'PY'
import json,sys,datetime
cp,ap=sys.argv[1],sys.argv[2]
ANNUAL,DED,PCT=10000,250,80
WAIT={"accident":0,"illness":14,"orthopedic":182,"wellness":0,"cosmetic":0}
EXCL={"Prescription i/d food","Therapeutic diet","Joint supplement","Nail trim","Boarding","Nutritional supplement"}
def days(a,b):
    da=datetime.date(*map(int,a.split("-")));db=datetime.date(*map(int,b.split("-")));return (db-da).days
d=json.load(open(cp));ch=False
for c in d:
    if c.get("status")!="classified": continue
    peril=(c.get("peril") or "illness").lower().strip()
    if peril not in WAIT: peril="illness"
    pe={"peril":peril,"deductible":DED,"reimburse_pct":PCT,"covered":True,"waiting_ok":True,"excluded_items":[]}
    try: pe["waiting_ok"]=days(c["policy_start"],c["claim_date"])>=WAIT[peril]
    except Exception: pe["waiting_ok"]=True
    if peril=="cosmetic" or c.get("preexisting_suspected") is True: pe["covered"]=False
    elif not pe["waiting_ok"]: pe["covered"]=False
    elif peril=="wellness" and "wellness" not in (c.get("addons") or []): pe["covered"]=False
    # exclusions: exact match against actual line items (hallucination impossible)
    pe["excluded_items"]=[i["desc"] for i in (c.get("line_items") or []) if i.get("desc") in EXCL]
    c["policy_eval"]=pe; c["status"]="policy_checked"; ch=True
if ch:
    json.dump(d,open(cp,"w"),indent=2)
    open(ap,"a").write(json.dumps({"event":"policy_checked","agent":"policy-engine(code)","ts":datetime.datetime.now(datetime.timezone.utc).isoformat()})+"\n")
    print("  policy_eval computed deterministically")
PY
fi

# 5. NECESSITY (LLM, annotation only) + 6. FRAUD (LLM) -> risk_scored
[ "$(cnt policy_checked)" -gt 0 ]&&{ echo "--- medical-necessity ---"; openclaw agent --agent medical-necessity --message "$F (1) read $CLAIMS; (2) for the claim with status policy_checked add necessity (verdict, notes); (3) do NOT change status; (4) write $CLAIMS. Reply ONLY: NECESSITY claim_id." >/dev/null 2>&1; }
stage fraud-anomaly policy_checked "(1) read $CLAIMS; (2) for the claim with status policy_checked add risk (score 0-100, flags); (3) set status risk_scored; (4) write $CLAIMS; (5) append a line to $AUD. Reply ONLY: RISK claim_id."

# 7. ADJUDICATION (CODE) — handles returned + risk_scored
if [ $(( $(cnt risk_scored) + $(cnt returned) )) -gt 0 ]; then echo "--- adjudication (code) ---"; python3 - "$CLAIMS" "$AUD" <<'PY'
import json,sys,datetime
cp,ap=sys.argv[1],sys.argv[2];ANNUAL=10000
d=json.load(open(cp));ch=False
for c in d:
    st=c.get("status")
    if st=="returned":
        c["recommendation"]="RETURNED";c["payout"]=0.0
        c["rationale"]="RETURNED: "+str(c.get("return_reason","incomplete documentation"))
        c["status"]="adjudication_drafted";ch=True;continue
    if st!="risk_scored": continue
    pe=c.get("policy_eval",{}) or {}
    if pe.get("covered") is False:
        c["recommendation"]="DENY";c["payout"]=0.0
        c["rationale"]="DENY: not covered (peril %s, waiting_ok %s)"%(pe.get("peril"),pe.get("waiting_ok"))
    else:
        excl=set(pe.get("excluded_items",[]) or [])
        ea=sum((i.get("amount",0) or 0) for i in (c.get("line_items") or []) if i.get("desc") in excl)
        cov=(c.get("invoice_total",0) or 0)-ea;ded=pe.get("deductible",250);pct=pe.get("reimburse_pct",80)/100.0
        raw=max(0,(cov-ded))*pct;c["payout"]=round(min(raw,ANNUAL),2)
        c["recommendation"]=("DENY" if cov<=0 else ("PARTIAL" if (excl or raw>ANNUAL) else "APPROVE"))
        c["rationale"]="%s: covered %s minus deductible %s at %d%% = %s"%(c["recommendation"],cov,ded,pe.get("reimburse_pct",80),c["payout"])
    c["status"]="adjudication_drafted";ch=True
if ch:
    json.dump(d,open(cp,"w"),indent=2)
    open(ap,"a").write(json.dumps({"event":"adjudication_drafted","agent":"adjudication(code)","ts":datetime.datetime.now(datetime.timezone.utc).isoformat()})+"\n")
    print("  adjudication written")
PY
fi

# 8. NOTIFIER (LLM) -> human gate
stage notifier adjudication_drafted "(1) read $CLAIMS; (2) for the claim with status adjudication_drafted set status human_review; (3) write $CLAIMS. Reply ONLY: NOTIFIED claim_id."
echo "--- audit-logger ---"; openclaw agent --agent audit-logger --message "$F ensure $AUD has one line per status transition in $CLAIMS; append missing ones; do not change statuses. Reply ONLY: AUDIT done." >/dev/null 2>&1
echo "=== pass complete $(date -u +%FT%TZ) ==="
