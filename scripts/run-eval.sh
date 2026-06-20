#!/bin/bash
# Per-claim LLM-pipeline evaluation over the synthetic corpus.
# Each claim runs in isolation (clean claims.json) so agent context never overflows.
# Usage: bash run-eval.sh [DATASET.json] [GROUND_TRUTH.json] [N]
export PATH="$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
set -u
ABS="$HOME/openclaw-insurance/workspace"
PIPE="$HOME/openclaw-insurance/scripts/run-pipeline.sh"
DS="${1:-$HOME/claims_dataset.json}"; GT="${2:-$HOME/ground_truth.json}"; N="${3:-40}"
RES="$HOME/eval_results.jsonl"; : > "$RES"
echo "Dataset: $DS | Ground truth: $GT | N=$N"
# stratified sample of N external_ids across the 4 ground-truth dispositions
mapfile -t IDS < <(python3 - "$GT" "$N" <<'PY'
import json,sys,random
gt=json.load(open(sys.argv[1])); N=int(sys.argv[2]); random.seed(7)
by={}
for g in gt: by.setdefault(g["disposition"],[]).append(g["external_id"])
per=max(1,N//len(by)); out=[]
for k in by:
    random.shuffle(by[k]); out+=by[k][:per]
random.shuffle(out)
for x in out[:N]: print(x)
PY
)
echo "selected ${#IDS[@]} claims; starting $(date)"
i=0
for id in "${IDS[@]}"; do
  i=$((i+1))
  echo '[]' > "$ABS/data/claims.json"; : > "$ABS/data/audit-log.jsonl"
  rm -f "$ABS/inbox/"* "$ABS/data/processed/"* 2>/dev/null
  python3 -c "import json;d=json.load(open('$DS'));c=[x for x in d if x['external_id']=='$id'][0];json.dump(c,open('$ABS/inbox/$id.json','w'))"
  bash "$PIPE" >/dev/null 2>&1
  python3 -c "import json;d=json.load(open('$ABS/data/claims.json'));c=d[0] if d else {};print(json.dumps({'external_id':'$id','status':c.get('status'),'recommendation':c.get('recommendation'),'payout':c.get('payout'),'policy_eval':c.get('policy_eval')}))" >> "$RES"
  echo "[$i/${#IDS[@]}] $id -> $(tail -1 "$RES" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('recommendation') or d.get('status'))")"
done
echo "finished $(date). Scoring:"
python3 "$HOME/score_eval.py" "$RES" "$GT"
