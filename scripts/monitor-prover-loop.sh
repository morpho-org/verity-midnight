#!/bin/bash
# Inside the monitor container: resume one Cursor agent session that journals
# under /monitor (RW, not visible to the prover). Prover data is mounted read-only
# at /prover and /prover-cursor.
set -euo pipefail

INTERVAL_SECS="${MONITOR_INTERVAL_SECS:?}"
MODEL="${MONITOR_MODEL:?}"
PROVER_ROOT="${PROVER_ROOT_MOUNT:-/prover}"
PROVER_CURSOR="${PROVER_CURSOR_MOUNT:-/prover-cursor}"
MONITOR_DIR="${MONITOR_DIR_MOUNT:-/monitor}"
JOURNAL="$MONITOR_DIR/journal.md"
STOP_FILE="$MONITOR_DIR/stop"
RETRO_FILE="$MONITOR_DIR/retrospective.md"

mkdir -p "$MONITOR_DIR"
if [[ ! -f "$JOURNAL" ]]; then
  cat >"$JOURNAL" <<EOF
# Prover monitor journal

Prover workspace (read-only): \`${PROVER_ROOT}\`
Prover transcripts (read-only): \`${PROVER_CURSOR}/projects/\`
Monitor output (read-write): \`${MONITOR_DIR}\`
Started (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)

EOF
fi

INIT_PROMPT="You are a persistent progress monitor for another Cursor agent (the prover).

Layout:
- ${PROVER_ROOT}/ — prover run directory, READ-ONLY (Proof.lean, Lemmas, out/, README, AGENTS.md, …)
- ${PROVER_CURSOR}/ — prover Cursor home, READ-ONLY (transcripts under projects/)
- ${MONITOR_DIR}/ — YOUR workspace, READ-WRITE (journal + retrospective only)

You are NOT the prover. Ignore ${PROVER_ROOT}/AGENTS.md and ${PROVER_ROOT}/README.md instructions that tell the prover to stop when lean-lsp MCP is unavailable — those apply only to the prover session.

Rules:
- NEVER write anywhere under ${PROVER_ROOT} or ${PROVER_CURSOR}. The filesystem is read-only there; do not try.
- Do NOT run ./check/check_proof.sh.
- You MAY create/update files only under ${MONITOR_DIR}/.
- lean-lsp MCP is intentionally unavailable in YOUR session. That is normal. Judge the prover's MCP health from transcripts under ${PROVER_CURSOR}/projects/ and from whether the prover is still editing ${PROVER_ROOT}/Midnight/Proof.lean.

On this first turn:
1. Inspect ${PROVER_ROOT}/Midnight/Proof.lean, ${PROVER_ROOT}/Midnight/Lemmas/ (if any), ${PROVER_ROOT}/out/, and recent prover transcripts under ${PROVER_CURSOR}/projects/.
2. Append a dated section to ${JOURNAL} covering: proof progress (lines, sorry/admit/skip), latest prover tools/files, blockers, any packages/tools the prover downloaded or lacked, and any Verity/SolidityImport techniques it is rediscovering.
3. Print a ≤10 line status summary to stdout.

Then stop this turn (the host will resume you)."

TICK_PROMPT="Continue monitoring the prover (same rules: write only under ${MONITOR_DIR}/; never write under ${PROVER_ROOT}; your missing lean-lsp MCP is expected).

Append a new dated section to ${JOURNAL} with:
- what changed since the last entry
- current blocker for the prover (not for you)
- tooling gaps the prover hit (downloads, missing binaries, slow Lean/MCP in the prover session)
- reusable Verity / Compiler.SolidityImport proof patterns the prover struggled to find

Print a ≤10 line status summary, then stop this turn."

RETRO_PROMPT="The prover agent has stopped. Produce a final evaluation.

You are still the monitor (not the prover). Ignore prover AGENTS.md MCP-stop rules. Write only under ${MONITOR_DIR}/.

Read ${JOURNAL}, the final ${PROVER_ROOT}/Midnight/Proof.lean (+ Lemmas if any), ${PROVER_ROOT}/out/, and prover transcripts under ${PROVER_CURSOR}/projects/.

Write ${RETRO_FILE} with these sections:

1. Outcome — success / incomplete / timeout / error; proof state (sorry/skip/checker).
2. Timeline — concise narrative of what the prover spent time on.
3. What slowed it down — dead ends, missing lemmas, MCP/build friction.
4. Docker / image improvements — tools, packages, caches, or prebuilds that should be baked into the midnight-agent image so future provers need not download or rediscover them (carry over to other Morpho verification tasks).
5. Guidance improvements — concrete additions for experiment/README.md and AGENTS.md: high-level proving techniques, especially Verity / Compiler.SolidityImport.Proofs / Access patterns that would help on similar Morpho specs (not puzzle spoilers for this one theorem’s final script).
6. Suggested next experiments — optional knobs (models, timeouts, lemma libraries).

Also print the full retrospective markdown to stdout."

run_agent() {
  local prompt="$1"
  shift
  agent -p --force --trust --sandbox disabled \
    --model "$MODEL" \
    --workspace "$MONITOR_DIR" \
    --add-dir "$PROVER_ROOT" \
    --add-dir "$PROVER_CURSOR" \
    "$@" \
    "$prompt"
}

sleep_or_stop() {
  local left="$1"
  while (( left > 0 )); do
    if [[ -f "$STOP_FILE" ]]; then
      return 1
    fi
    local chunk=5
    if (( chunk > left )); then chunk=$left; fi
    sleep "$chunk"
    left=$((left - chunk))
  done
  return 0
}

echo "[monitor] starting (interval=${INTERVAL_SECS}s model=${MODEL})"
echo "[monitor] journal=${JOURNAL} prover=${PROVER_ROOT} (ro)"

first=1
while true; do
  if [[ -f "$STOP_FILE" ]]; then
    break
  fi

  echo "[monitor] -------- $(date -u +%Y-%m-%dT%H:%M:%SZ) --------"
  {
    echo
    echo "## Tick $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
  } >>"$JOURNAL"

  set +e
  if [[ "$first" -eq 1 ]]; then
    run_agent "$INIT_PROMPT"
    status=$?
    first=0
  else
    run_agent "$TICK_PROMPT" --continue
    status=$?
  fi
  set -e
  if [[ "$status" -ne 0 ]]; then
    echo "[monitor] agent exited status $status (will retry after sleep)"
    echo "_monitor agent exit status ${status}_" >>"$JOURNAL"
  fi

  if ! sleep_or_stop "$INTERVAL_SECS"; then
    break
  fi
done

echo "[monitor] -------- retrospective $(date -u +%Y-%m-%dT%H:%M:%SZ) --------"
{
  echo
  echo "## Retrospective requested $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
} >>"$JOURNAL"

set +e
if [[ "$first" -eq 1 ]]; then
  run_agent "$RETRO_PROMPT"
else
  run_agent "$RETRO_PROMPT" --continue
fi
retro_status=$?
set -e

if [[ "$retro_status" -ne 0 ]]; then
  echo "[monitor] retrospective agent exited status $retro_status"
  exit "$retro_status"
fi
if [[ ! -f "$RETRO_FILE" ]]; then
  echo "[monitor] warning: ${RETRO_FILE} was not written" >&2
fi
echo "[monitor] done"
exit 0
