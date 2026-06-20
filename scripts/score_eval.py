#!/usr/bin/env python3
# Score per-claim eval results (jsonl) vs ground truth. Usage: score_eval.py results.jsonl ground_truth.json
import json,sys
res=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
gt={g["external_id"]:g for g in json.load(open(sys.argv[2]))}
labels=["APPROVE","PARTIAL","DENY","RETURNED"]
def pred_disp(r):
    if r.get("recommendation") in labels: return r["recommendation"]
    s=(r.get("status") or "").lower()
    if "return" in s: return "RETURNED"
    return r.get("recommendation") or s.upper() or "NONE"
n=reach=dok=0; pe=[]; cm={a:{b:0 for b in labels+["OTHER"]} for a in labels}
for r in res:
    g=gt.get(r["external_id"]);
    if not g: continue
    n+=1
    if r.get("status")=="human_review" or (r.get("recommendation") in labels) or "return" in (r.get("status") or "").lower(): reach+=1
    pd=pred_disp(r); td=g["disposition"]
    col=pd if pd in labels else "OTHER"; cm[td][col]+=1
    if pd==td: dok+=1
    if r.get("payout") is not None and g.get("payout") is not None: pe.append(abs(r["payout"]-g["payout"]))
print(f"N scored:            {n}")
print(f"reached terminal:    {reach}/{n} ({100*reach/max(1,n):.1f}%)")
print(f"disposition accuracy:{dok}/{n} ({100*dok/max(1,n):.1f}%)")
print(f"payout MAE (paid):   ${(sum(pe)/len(pe)) if pe else 0:.2f}  (n={len(pe)})")
print("\nConfusion (rows=truth, cols=pred):")
hdr=labels+["OTHER"]; print("           "+" ".join(f"{h[:5]:>6}" for h in hdr))
for a in labels: print(f"{a:>10} "+" ".join(f"{cm[a][b]:>6}" for b in hdr))
