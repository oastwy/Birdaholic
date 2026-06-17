#!/bin/bash
# One-shot orchestrator (run detached on the server):
#   1) back up every manifest.json + the current index
#   2) archive the old backfill state for a clean combined pass
#   3) run the backfill with --purge-nonopen-inat --compress-existing
# Safe to re-run: backup is timestamped; backfill itself is resumable.
set -u
LOG=/data/backfill_orchestrator.log
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p /data/backups

echo "$(date '+%F %T') start ts=$TS" >> "$LOG"
find /data/species -name manifest.json | tar czf "/data/backups/manifests_$TS.tar.gz" -T - \
  && echo "$(date '+%F %T') manifests backed up" >> "$LOG"
cp -a /data/indexes/species_media_index.json "/data/backups/species_media_index_$TS.json" 2>/dev/null
mv -f /data/.inat_photo_backfill_state.json "/data/backups/inat_state_$TS.json" 2>/dev/null \
  && echo "$(date '+%F %T') state archived" >> "$LOG"

echo "$(date '+%F %T') launching combined backfill" >> "$LOG"
python3 -u /data/server/backfill_inat_photos.py \
  --data-dir /data --base-url http://124.223.101.188:8080 \
  --max-images 3 --per-page 30 --sleep 0.8 --jpeg-quality 72 --max-image 1600 \
  --purge-nonopen-inat --compress-existing \
  >> /data/inat_backfill.log 2>&1
echo "$(date '+%F %T') backfill exited rc=$?" >> "$LOG"
