#!/bin/bash
# ClaimPilot SINGLE-AGENT baseline (Reviewer 2, point 2).
# ONE LLM agent performs extraction + usability gate + peril classification in a single turn.
# The deterministic policy/adjudication engine below is IDENTICAL to run-pipeline-eval.sh,
# so any performance difference is attributable to the LLM decomposition, not the decision logic.
# Reuses the registered 'doc-extractor' agent id (gpt-5-mini) as the solo agent — no config change.
export PATH="$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
set -u
ABS="$HOME/openclaw-insurance/workspace"; CLAIMS="$ABS/data/claims.json"; AUD="$ABS/data/audit-log.jsonl"
[ -f "$CLAIMS" ] || echo '[]' > "$CLAIMS"; mkdir -p "$ABS/inbox" "$ABS/data/processed"
cnt(){ python3 -c "import json;d=json.load(open('$CLAIMS'));print(sum(1 for c in d if c.get('status')=='$1'))" 2>/dev/null||echo 0; }
F="You MUST call your file tools this turn. A reply without an actual tool call and file write is a FAILURE. Do it now:"
stage(){ local a="$1" st="$2" m="$3"; [ "$(cnt "$st")" -gt 0 ]||return 0
  for t in 1 2 3 4 5; do openclaw agent --agent "$a" --message "$F $m" >"$HOME/eval_logs/${a}.$$.log" 2>&1
    [ "$(cnt "$st")" -eq 0 ]&&return 0; done; echo "  WARN: $a left $(cnt "$st") at $st"; }
mkdir -p "$HOME/eval_logs"

# 1. INTAKE (code) — identical to multi-agent pipeline
python3 - "$CLAIMS" "$ABS" <<'PY'
import json,sys,os,glob,random,datetime
cp,ABS=sys.argv[1],sys.argv[2]
d=json.load(open(cp))
for f in glob.glob(os.path.join(ABS,"inbox","*.json")):
    src=json.load(open(f)); b=os.path.basename(f)
    d.append({"claim_id":"CLM-%s-%04d"%(datetime.date.today().strftime("%Y%m%d"),random.randint(0,9999)),
              "source_file":b,"external_id":src.get("external_id"),"status":"received"})
    os.replace(f,os.path.join(ABS,"data","processed",b))
json.dump(d,open(cp,"w"),indent=2)
PY

# 2. SOLO AGENT (LLM) — extraction + usability gate + peril classification in ONE turn
stage doc-extractor received "(1) read $CLAIMS; (2) for the claim with status received, read its source document in $ABS/data/processed/ (named in source_file); (3) copy these fields into the claim: pet, policy_id, policy_start, claim_date, addons, diagnosis, treatment, line_items, invoice_total; (4) IF diagnosis is empty, missing or unreadable: set status to returned and return_reason to 'missing or illegible diagnosis' and do nothing else; (5) OTHERWISE classify the peril as EXACTLY ONE of: accident, illness, orthopedic, cosmetic, wellness. accident=trauma/foreign body/laceration/fracture/hit-by-car; orthopedic=cruciate or CCL rupture, luxating patella, hip dysplasia; cosmetic=elective ear crop, declaw, cosmetic dental; wellness=routine or annual exam, vaccination, heartworm prevention; illness=everything else. Set preexisting_suspected to true ONLY if the record explicitly states the condition predates policy_start, otherwise false. Then set status to classified. (6) write $CLAIMS. Numbers must come from the document, never inferred. Reply ONLY: SOLO claim_id status."

# 2b. NORMALISE state (code owns transitions, not the LLM) — matches eval harness logic
python3 - "$CLAIMS" <<'PY2'
import json,sys
cp=sys.argv[1]; d=json.load(open(cp))
for c in d:
    if c.get("peril") and c.get("status") in ("received","extracted","policy_checked","classified"):
        c["status"]="classified"
    elif c.get("status")=="received" and not (c.get("diagnosis") or "").strip() and (c.get("invoice_total") is not None or c.get("line_items")):
        c["status"]="returned"; c.setdefault("return_reason","missing or illegible diagnosis")
json.dump(d,open(cp,"w"),indent=2)
PY2

# 3. POLICY ENGINE + RISK STUB + ADJUDICATION (all code) — IDENTICAL to run-pipeline-eval.sh
python3 - "$CLAIMS" "$AUD" <<'PY'
import json,sys,datetime
cp,ap=sys.argv[1],sys.argv[2]
ANNUAL,DED,PCT=10000,250,80
WAIT={"accident":0,"illness":14,"orthopedic":182,"wellness":0,"cosmetic":0}
EXCL={"Prescription i/d food","Therapeutic diet","Joint supplement","Nail trim","Boarding","Nutritional supplement"}
def days(a,b):
    da=datetime.date(*map(int,a.split("-")));db=datetime.date(*map(int,b.split("-")));return (db-da).days
d=json.load(open(cp))
for c in d:
    if c.get("status")=="classified":
        p=(c.get("peril") or "illness").lower().strip()
        if p not in WAIT: p="illness"
        pe={"peril":p,"deductible":DED,"reimburse_pct":PCT,"covered":True,"waiting_ok":True,"excluded_items":[]}
        try: pe["waiting_ok"]=days(c["policy_start"],c["claim_date"])>=WAIT[p]
        except Exception: pass
        if p=="cosmetic" or c.get("preexisting_suspected") is True: pe["covered"]=False
        elif not pe["waiting_ok"]: pe["covered"]=False
        elif p=="wellness" and "wellness" not in (c.get("addons") or []): pe["covered"]=False
        pe["excluded_items"]=[i["desc"] for i in (c.get("line_items") or []) if i.get("desc") in EXCL]
        c["policy_eval"]=pe; c["risk"]={"score":0,"flags":[]}; c["status"]="risk_scored"
    if c.get("status")=="returned":
        c.update(recommendation="RETURNED",payout=0.0,status="adjudication_drafted",
                 rationale="RETURNED: "+str(c.get("return_reason","incomplete documentation")))
    elif c.get("status")=="risk_scored":
        pe=c.get("policy_eval",{}) or {}
        if pe.get("covered") is False:
            c.update(recommendation="DENY",payout=0.0,rationale="DENY: not covered")
        else:
            excl=set(pe.get("excluded_items",[]) or [])
            ea=sum((i.get("amount",0) or 0) for i in (c.get("line_items") or []) if i.get("desc") in excl)
            cov=(c.get("invoice_total",0) or 0)-ea
            raw=max(0,cov-pe.get("deductible",DED))*pe.get("reimburse_pct",PCT)/100.0
            c["payout"]=round(min(raw,ANNUAL),2)
            c["recommendation"]=("DENY" if cov<=0 else ("PARTIAL" if (excl or raw>ANNUAL) else "APPROVE"))
            c["rationale"]="%s: covered %s"%(c["recommendation"],cov)
        c["status"]="adjudication_drafted"
    if c.get("status")=="adjudication_drafted": c["status"]="human_review"
json.dump(d,open(cp,"w"),indent=2)
open(ap,"a").write(json.dumps({"event":"eval_pass_single","ts":datetime.datetime.now(datetime.timezone.utc).isoformat()})+"\n")
PY
