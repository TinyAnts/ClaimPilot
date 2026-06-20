#!/bin/bash
# Register Phase-1 cron jobs. The pipeline poll exits at $0 when inbox/ is empty.
set -e
PROJ="$HOME/openclaw-insurance"
if [ -f "$PROJ/.env" ]; then set -a; . "$PROJ/.env"; set +a; fi
export OPENCLAW_CONFIG_PATH="$PROJ/openclaw.json"
export OPENCLAW_STATE_DIR="$HOME/.openclaw-insurance-state"

# Pipeline pass every 10 min: each agent reads claims at its input status and advances them.
# A single message drives one full sweep; agents no-op if there is nothing at their status.
openclaw cron add --name "insurance-pipeline" \
  --cron "*/10 * * * *" --tz "America/New_York" --session isolated \
  --message "Run one claims pipeline pass: intake new inbox files, then advance every claim one stage. If inbox empty AND no claims pending, exit without model calls." \
  --model "openai/gpt-5-mini"

# Notifier sweep every 5 min: deliver any human-approved/denied decisions to Telegram.
openclaw cron add --name "insurance-notifier" \
  --cron "*/5 * * * *" --tz "America/New_York" --session isolated \
  --message "Deliver decisions for claims at status approved|denied. Mark notified then closed." \
  --model "openai/gpt-5-mini" --announce --channel telegram

# Phase 3 (commented): weekly pattern review
# openclaw cron add --name "insurance-pattern-review" \
#   --cron "0 7 * * 1" --tz "America/New_York" --session isolated \
#   --message "Weekly: denial-rate drift, fraud clusters, policy gaps -> patterns.json" \
#   --model "openai/gpt-5.5"

echo "Phase-1 cron registered:"
openclaw cron list
