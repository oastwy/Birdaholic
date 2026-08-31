#!/bin/bash
# Master orchestrator (run detached): repeatedly run the photo backfill until the
# residual non-open iNat image count stops dropping (converged), then run the
# location backfill ONCE (safe — no photo pass running at that point), then stop.
# Launch with: setsid bash /data/server/backfill_loop.sh </dev/null >/dev/null 2>&1 &
set -u
LOG=/data/backfill_loop.log
PY=/data/server/backfill_inat_photos.py

# Kill any photo backfill already running, so we don't double-write manifests.
PIDS=$(ps -eo pid,comm,args | awk '$2 ~ /python/ && /backfill_inat_photos/ {print $1}')
[ -n "$PIDS" ] && kill -9 $PIDS 2>/dev/null && sleep 2

count_residual() {
  python3 -c "
import json,glob
n=0
for mp in glob.glob('/data/species/*/manifest.json'):
    try: m=json.load(open(mp))
    except: continue
    for i in m.get('images',[]):
        if str(i.get('source','')).lower()=='inaturalist' and str(i.get('license') or '').lower() not in ('cc0','cc-by','cc-by-sa'): n+=1
print(n)
"
}

prev=$(count_residual)
echo "$(date '+%F %T') LOOP start, residual=$prev" >> "$LOG"
for pass in $(seq 1 12); do
  echo "$(date '+%F %T') pass $pass start (residual=$prev)" >> "$LOG"
  python3 -u "$PY" --data-dir /data --base-url http://your-server-ip:8080 \
    --max-images 3 --per-page 30 --sleep 0.5 --jpeg-quality 72 --max-image 1600 \
    --timeout 20 --workers 16 --purge-nonopen-inat --compress-existing \
    >> /data/inat_backfill.log 2>&1
  cur=$(count_residual)
  drop=$((prev - cur))
  echo "$(date '+%F %T') pass $pass done (residual=$cur, drop=$drop)" >> "$LOG"
  if [ "$cur" -le 0 ] || [ "$drop" -lt 50 ]; then
    echo "$(date '+%F %T') CONVERGED (residual=$cur). running location backfill..." >> "$LOG"
    python3 -u /data/server/backfill_locations.py >> /data/inat_backfill.log 2>&1
    echo "$(date '+%F %T') location backfill done. ALL COMPLETE (residual=$cur)." >> "$LOG"
    exit 0
  fi
  prev=$cur
done
echo "$(date '+%F %T') hit 12-pass cap, residual=$prev (still running location backfill)." >> "$LOG"
python3 -u /data/server/backfill_locations.py >> /data/inat_backfill.log 2>&1
echo "$(date '+%F %T') location backfill done after cap." >> "$LOG"
