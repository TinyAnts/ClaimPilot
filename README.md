# ClaimPilot — an open multi-agent pipeline for veterinary insurance claims adjudication

ClaimPilot is a self-hosted, **multi-agent** system that turns an incoming veterinary insurance claim
(invoice + records) into a **drafted adjudication recommendation** — extract → policy-match → risk-score →
adjudicate — and then **stops for a human** to approve, deny, or return it. It runs on a single commodity
machine on top of the [OpenClaw](https://github.com/openclaw/openclaw) gateway, with cheap-tier LLM agents
and a deterministic adjudication step.

> **Status: research prototype.** Validated only on synthetic data. It drafts; a licensed human decides.
> No claim is ever paid or denied autonomously. Not a clinically or actuarially validated product.

---

## Why this exists

The North American pet-insurance market reached **USD 5.2 B in written premium and 7.03 M insured pets in
2024**, implying millions of document-heavy, rules-bound claims per year — a strong fit for agentic
automation *with a human gate*. ClaimPilot is a reproducible reference implementation plus an honest,
measured evaluation of how such a pipeline actually behaves once deployed.

## Architecture

Nine roles operate over file-based shared state; the status chain is strict and auditable:

```
received → extracted → policy_checked → risk_scored → adjudication_drafted → human_review
```

![Architecture](figures/fig8_flowchart.png)

| # | Role | Engine | Function |
|---|------|--------|----------|
| 1 | Intake | gpt-5-mini | register inbound claim documents |
| 2 | DocExtractor | gpt-5-mini | parse invoice + records into structured fields |
| 3 | PolicyMatcher | gpt-5-mini | coverage, exclusions, deductible, waiting period → `policy_eval` |
| 4 | MedicalNecessity | gpt-5-mini | treatment-vs-diagnosis support note |
| 5 | Fraud/Anomaly | gpt-5-mini | risk score + flags |
| 6 | **Adjudication** | **deterministic code** | closed-form payout + recommendation |
| 7 | Notifier | gpt-5-mini | route draft to the human gate |
| 8 | AuditLogger | gpt-5-mini | reconcile the immutable transition log |
| 9 | PatternReview | gpt-5.5 (weekly) | denial-rate drift, fraud clusters |

Every LLM stage is wrapped in a **verify-and-retry** loop; all deterministic work lives in code.

## Deployment options

**Human gate via existing tools.** Because it runs on a multi-channel gateway, drafts can be delivered and approve/deny/return decisions collected through the messaging tools a team already uses — Slack, Microsoft Teams, Discord, Telegram, or e-mail — with one gateway binding all of them and a reply or reaction advancing the claim. Tiered routing can send high-risk (over-approval-prone) claims to a senior reviewer.

**Local or headless cloud.** The same gateway and agent definitions deploy unchanged from a single board to a headless VPS or container, reachable over a secure overlay network (e.g., Tailscale) so authorised staff review from anywhere without exposing the service publicly. Any real-data deployment needs the usual data-protection posture (access control, encryption, retention, redundancy).

## Key findings (from deployment + a 40-claim pilot)

1. **Tool-protocol compatibility is a model-selection criterion.** Two of four candidate models returned
   HTTP 400 on the gateway's tool schema; `gpt-5-mini` works. Capability leaderboards don't report this.
2. **Cheap models narrate instead of calling tools.** Explicit, tool-forcing prompts + a verify-and-retry
   wrapper raised first-attempt tool execution to ~100% and produced **100% end-to-end completion (40/40)**.
3. **Don't make an LLM do arithmetic.** As an LLM agent the payout step succeeded 0/10; in code it is
   **100%, payout MAE $0.00**.
4. **Robustness ≠ accuracy.** The robust pipeline was only **50% accurate** on disposition, with a
   systematic **over-approval bias** (26 predicted APPROVE vs 10 true) and **0/10 RETURNED detected** —
   which is exactly why the human gate is essential. Per-class metrics confirm it: APPROVE precision is only **38.5%**, macro-F1 **43.1%**, **Cohen's κ = 0.33** (fair agreement), and **16 of 40** claims are steered toward payment in error. Payout MAE was **$183.88**.

Cost: ≈ **$0.012 per claim** on the cheap tier (≈35× higher all-frontier); idle passes cost $0.

## Repository layout

```
config/        reference openclaw.json (JSON5), .env.example, telegram-block.txt
workspace/     agent definitions (SOUL.md per role), 4-layer memory files, policy rules, sample claim
scripts/       deploy + run + evaluate (setup, start/stop, run-pipeline, run-eval, score_eval, cron-setup)
dataset/       150-claim synthetic corpus + independent ground-truth labels + summary/eval stats
figures/       all 13 paper figures (PNG)
ClaimPilot_figures.ipynb, make_figs.py   regenerate every figure from dataset/*.json
```

## Quick start

Prereqs: a Linux box, Node 24 (or 22.19+), `npm i -g openclaw@latest`, an OpenAI API key.

```bash
# 1. lay down the project
mkdir -p ~/openclaw-insurance && cp -r workspace ~/openclaw-insurance/
cp config/openclaw.json ~/.openclaw/openclaw.json        # gateway reads ~/.openclaw/openclaw.json
cp config/.env.example ~/.openclaw/.env                   # then fill it

# 2. secrets (on the box only)
#    OPENAI_API_KEY=sk-...   OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)

# 3. validate + start
openclaw config validate && openclaw gateway restart && openclaw status

# 4. drop a claim and run one pass
cp ~/openclaw-insurance/workspace/samples/sample-claim-01.json ~/openclaw-insurance/workspace/inbox/
bash scripts/run-pipeline.sh
cat ~/openclaw-insurance/workspace/data/claims.json
```

Schedule hands-off operation with `scripts/cron-setup.sh` (every 5 min, `flock`-guarded; idle = $0).

## Reproduce the evaluation

```bash
bash scripts/run-eval.sh dataset/claims_dataset.json dataset/ground_truth.json 40
# prints completion rate, disposition accuracy, payout MAE, and a 4×4 confusion matrix
```

## Reproduce the figures

```bash
pip install matplotlib pillow
python3 make_figs.py          # or open ClaimPilot_figures.ipynb and run all cells
```

## Dataset

`dataset/claims_dataset.json` — 150 synthetic claims (no real client/patient data).
`dataset/ground_truth.json` — independent reference labels (disposition + payout + `policy_eval`).
Mix: 62 APPROVE / 22 PARTIAL / 48 DENY / 18 RETURNED; invoice mean $1,404; payout mean $1,301.

## Known gaps / roadmap

- No `returned` route in the orchestrator yet (the source of the 0% RETURNED recall) — add it next.
- Add a self-consistency / confidence check on the policy-matcher to cut the over-approval bias.
- Evaluate at full corpus scale and on de-identified real claims.

## License

MIT — see `LICENSE`.
