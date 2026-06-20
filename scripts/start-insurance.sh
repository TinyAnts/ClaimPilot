#!/bin/bash
# Start the insurance gateway on port 19789 with isolated config + state.
set -e
PROJ="$HOME/openclaw-insurance"

# load secrets from the project .env (kept on box only)
if [ -f "$PROJ/.env" ]; then set -a; . "$PROJ/.env"; set +a; else
  echo "ERROR: $PROJ/.env missing. Copy .env.example -> .env and fill it (Step 3)."; exit 1; fi

export OPENCLAW_CONFIG_PATH="$PROJ/openclaw.json"
export OPENCLAW_STATE_DIR="$HOME/.openclaw-insurance-state"

echo "Starting insurance gateway (config=$OPENCLAW_CONFIG_PATH state=$OPENCLAW_STATE_DIR port=19789)"
openclaw gateway start --port 19789
openclaw gateway status --deep
