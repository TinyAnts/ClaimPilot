#!/bin/bash
# Step 0 — audit the existing box and back it up. Changes NOTHING.
set -u
echo "===================== OPENCLAW INVENTORY ====================="
echo "-- date:        $(date)"
echo "-- node:        $(node --version 2>/dev/null || echo 'NOT INSTALLED')"
echo "-- openclaw:    $(openclaw --version 2>/dev/null || echo 'NOT INSTALLED')"
echo
echo "-- default-profile gateway status:"
openclaw gateway status --deep 2>/dev/null || echo "   (no default gateway / not installed)"
echo
echo "-- cron jobs (default profile):"
openclaw cron list 2>/dev/null || echo "   (none / not available)"
echo
echo "-- ~/.openclaw contents:"
ls -la "$HOME/.openclaw" 2>/dev/null || echo "   (~/.openclaw does not exist)"
echo
echo "-- port 19789 in use?"
( ss -ltnp 2>/dev/null | grep 19789 ) || echo "   19789 is FREE (good)"
echo
echo "===================== BACKUP ====================="
if [ -d "$HOME/.openclaw" ]; then
  TS=$(date +%Y%m%d-%H%M%S)
  tar czf "$HOME/openclaw-backup-$TS.tgz" -C "$HOME" .openclaw \
    && echo "Backup written: $HOME/openclaw-backup-$TS.tgz"
else
  echo "Nothing to back up (~/.openclaw absent)."
fi
echo "Done. Read the output above BEFORE running setup-insurance.sh."
