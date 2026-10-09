#!/bin/bash
# Inside the monitor container: periodically ask the Cursor agent for a
# read-only status report of the prover working in /work.
set -euo pipefail

INTERVAL_SECS="${MONITOR_INTERVAL_SECS:?}"
MODEL="${MONITOR_MODEL:?}"
PROVER_CURSOR="${PROVER_CURSOR_MOUNT:-/prover-cursor}"

PROMPT="You are a read-only progress monitor for another Cursor agent (the prover) working in /work on Midnight.updatePositionViewProperties.

Do NOT edit any files. Do NOT run ./check/check_proof.sh. Do NOT write under /work/Midnight.

Inspect and summarize in at most 10 lines:
1. /work/Midnight/Proof.lean and /work/Midnight/Lemmas/ — line count, whether sorry/admit remain, whether the main theorem looks in progress or complete.
2. Recent prover activity from transcripts under ${PROVER_CURSOR}/projects/ (latest tool names / files touched), if present.
3. /work/out/ (mcp-unavailable or axioms) if present.
4. Any obvious blocker.

Print only the status report, then stop this turn."

echo "[monitor] starting (interval=${INTERVAL_SECS}s model=${MODEL})"
while true; do
  echo "[monitor] -------- $(date -u +%Y-%m-%dT%H:%M:%SZ) --------"
  set +e
  agent -p --force --trust --sandbox disabled \
    --model "$MODEL" \
    --workspace /work \
    "$PROMPT"
  status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    echo "[monitor] agent exited status $status (will retry after sleep)"
  fi
  sleep "$INTERVAL_SECS"
done
