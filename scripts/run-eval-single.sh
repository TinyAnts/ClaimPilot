#!/bin/bash
# Single-agent baseline evaluation driver. Identical structure to run-eval-fast.sh
# (same sampler, same per-claim reset, same session isolation, same scorer) but points
# at run-pipeline-single.sh. Results -> ~/eval_results_single.jsonl.
# Usage: bash run-eval-single.sh [DATASET.json] [GROUND_TRUTH.json] [N] [--ids FILE]
export PATH="$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
set -u
ABS="/home/raj/openclaw-insurance/workspace"
PIPE="$HOME/openclaw-insurance/scripts/run-pipeline-single.sh"
LOGDIR="$HOME/eval_logs"; mkdir -p "$LOGDIR"

DS="$HOME/claims_dataset.json"; GT="$HOME/ground_truth.json"; N=40
IDFILE=""; POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --ids) IDFILE="$2"; shift 2 ;;
    *)     POS+=("$1"); shift ;;
  esac
done
[ ${#POS[@]} -ge 1 ] && DS="${POS[0]}"
[ ${#POS[@]} -ge 2 ] && GT="${POS[1]}"
[ ${#POS[@]} -ge 3 ] && N="${POS[2]}"

RES="$HOME/eval_results_single.jsonl"; : > "$RES"
if [ -n "$IDFILE" ]; then
  echo "SINGLE-AGENT | Dataset: $DS | GT: $GT | ID-list: $IDFILE"
  mapfile -t IDS < <(grep -oP 'SYN-\d+' "$IDFILE")
else
  echo "SINGLE-AGENT | Dataset: $DS | GT: $GT | N=$N"
  mapfile -t IDS < <(python3 - "$GT" "$N" <<'PY'
import json,sys,random
gt=json.load(open(sys.argv[1])); N=int(sys.argv[2]); random.seed(7)
if N>=len(gt):
    ids=[g["external_id"] for g in gt]; random.shuffle(ids)
    [print(x) for x in ids]; sys.exit(0)
by={}
for g in gt: by.setdefault(g["disposition"],[]).append(g["external_id"])
per=max(1,N//len(by)); out=[]
for k in by:
    random.shuffle(by[k]); out+=by[k][:per]
random.shuffle(out)
for x in out[:N]: print(x)
PY
)
fi

echo "selected ${#IDS[@]} claims; starting $(date)"
i=0
for id in "${IDS[@]}"; do
  i=$((i+1))
  echo '[]' > "$ABS/data/claims.json"; : > "$ABS/data/audit-log.jsonl"
  rm -f "$ABS/inbox/"* "$ABS/data/processed/"* 2>/dev/null
  rm -rf "$HOME"/.openclaw/agents/*/sessions/* 2>/dev/null   # session isolation (same as fast harness)
  python3 -c "import json;d=json.load(open('$DS'));c=[x for x in d if x['external_id']=='$id'][0];json.dump(c,open('$ABS/inbox/$id.json','w'))"
  bash "$PIPE" > "$LOGDIR/single_$id.log" 2>&1
  python3 -c "import json;d=json.load(open('$ABS/data/claims.json'));c=([x for x in d if x.get('external_id')=='$id']+[{}])[0];print(json.dumps({'external_id':'$id','n_in_file':len(d),'status':c.get('status'),'recommendation':c.get('recommendation'),'payout':c.get('payout'),'policy_eval':c.get('policy_eval')}))" >> "$RES"
  st=$(tail -1 "$RES" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('recommendation') or d.get('status') or 'NONE')")
  echo "[$i/${#IDS[@]}] $id -> $st"
done
echo "finished $(date). Scoring:"
python3 "$HOME/score_eval.py" "$RES" "$GT"
