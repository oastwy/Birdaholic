#!/bin/bash
# Self-healing guard for the iNaturalist photo backfill.
# Cron runs this periodically: if the backfill isn't running and hasn't yet
# made a full pass over every species, relaunch it (detached, resumable).
# Once the state file records every species (a full pass finished), it removes
# its own cron entry and stops. Safe to run repeatedly.
set -u
LOG=/data/backfill_guard.log
SCRIPT=/data/server/backfill_inat_photos.py
STATE=/data/.inat_photo_backfill_state.json

# Already running? nothing to do.
if pgrep -f backfill_inat_photos.py >/dev/null 2>&1; then
  exit 0
fi

TOTAL=$(ls /data/species 2>/dev/null | wc -l)
PROCESSED=$(python3 -c "import json;print(len(json.load(open('$STATE')).get('species',{})))" 2>/dev/null || echo 0)

if [ "$TOTAL" -gt 0 ] && [ "$PROCESSED" -ge "$TOTAL" ]; then
  echo "$(date '+%F %T') complete (processed=$PROCESSED/$TOTAL); removing cron" >> "$LOG"
  crontab -l 2>/dev/null | grep -v backfill_guard.sh | crontab -
  exit 0
fi

echo "$(date '+%F %T') relaunch (processed=$PROCESSED/$TOTAL)" >> "$LOG"
cd /data || exit 1
setsid bash -c "nohup python3 -u $SCRIPT --data-dir /data --base-url http://your-server-ip:8080 --max-images 3 --per-page 30 --sleep 0.8 --jpeg-quality 72 --max-image 1600 >> /data/inat_backfill.log 2>&1" </dev/null >/dev/null 2>&1 &
exit 0
