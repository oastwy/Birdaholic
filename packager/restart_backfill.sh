#!/bin/bash
# Kill any running backfill PYTHON process (filtering on comm==python avoids the
# self-match trap where a shell's own command line contains the script name),
# then run the combined purge+replace+compress backfill in the foreground of
# this (detached) script. Launch me with: setsid bash restart_backfill.sh &
PIDS=$(ps -eo pid,comm,args | awk '$2 ~ /python/ && /backfill_inat_photos/ {print $1}')
if [ -n "$PIDS" ]; then
  kill -9 $PIDS 2>/dev/null
  sleep 1
fi
cd /data || exit 1
exec python3 -u /data/server/backfill_inat_photos.py \
  --data-dir /data --base-url http://124.223.101.188:8080 \
  --max-images 3 --per-page 30 --sleep 0.5 --jpeg-quality 72 --max-image 1600 \
  --timeout 20 --workers 16 --purge-nonopen-inat --compress-existing \
  >> /data/inat_backfill.log 2>&1
