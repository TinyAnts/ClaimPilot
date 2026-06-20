#!/bin/bash
# Stop the insurance gateway. Deletes NOTHING — state persists, costs go to $0.
set -e
PROJ="$HOME/openclaw-insurance"
export OPENCLAW_CONFIG_PATH="$PROJ/openclaw.json"
export OPENCLAW_STATE_DIR="$HOME/.openclaw-insurance-state"
openclaw gateway stop || true
echo "Insurance gateway stopped. Restart with start-insurance.sh. Nothing was deleted."
