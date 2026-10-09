#!/bin/bash
# Fresh trial each invocation: copy experiment/ → runs/<id>/, run agent there,
# and on success extract the proof to results/<id>/. Next run never sees prior proofs.
set -euo pipefail

cd "$(dirname "$0")"

PLATFORM="${PLATFORM:-linux/amd64}"
IMAGE="${IMAGE:-midnight-agent}"
AGENT_TIMEOUT="${AGENT_TIMEOUT:-120m}"
AGENT_MODEL="${AGENT_MODEL:-gpt-5.6-sol-high}"
# Second Cursor agent that journals progress and writes a retrospective.
MONITOR="${MONITOR:-1}"
MONITOR_MODEL="${MONITOR_MODEL:-$AGENT_MODEL}"
MONITOR_INTERVAL="${MONITOR_INTERVAL:-2m}"
# How long to wait for the monitor's final retrospective after the prover stops.
MONITOR_RETRO_TIMEOUT="${MONITOR_RETRO_TIMEOUT:-20m}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
TEMPLATE="$PWD/experiment"
RUN_DIR="$PWD/runs/$RUN_ID"
# Monitor state is outside the prover workspace so the prover cannot see or
# be affected by journal / retrospective writes.
MONITOR_DIR="$PWD/monitor-logs/$RUN_ID"
RESULT_DIR="$PWD/results/$RUN_ID"
CACHE_DIR="$PWD/cache"
ROOT="$PWD"

parse_duration_secs() {
  local d="$1"
  case "$d" in
    *s) echo "${d%s}" ;;
    *m) echo $(( ${d%m} * 60 )) ;;
    *h) echo $(( ${d%h} * 3600 )) ;;
    *) echo "$d" ;;
  esac
}

mkdir -p "$PWD/runs" "$PWD/results" "$PWD/monitor-logs" "$CACHE_DIR"

# Seed package cache from a leftover template .lake once, then drop it from experiment/.
if [[ ! -d "$CACHE_DIR/packages" && -d "$TEMPLATE/.lake/packages" ]]; then
  echo "Seeding cache/ from experiment/.lake/packages"
  cp -a "$TEMPLATE/.lake/packages" "$CACHE_DIR/packages"
fi
if [[ -d "$TEMPLATE/.lake" ]]; then
  echo "Removing experiment/.lake (template must stay clean)"
  rm -rf "$TEMPLATE/.lake"
fi
rm -rf "$TEMPLATE/out"

echo "Checking experiment/ start state (frozen + stub Proof.lean)"
python3 "$TEMPLATE/check/check_frozen.py" --start

echo "Preparing run $RUN_ID"
mkdir -p "$RUN_DIR"
# No .lake / out from the template — each trial starts from the stub proof only.
cp -a "$TEMPLATE/." "$RUN_DIR/"
rm -rf "$RUN_DIR/.lake" "$RUN_DIR/out"

docker build --platform "$PLATFORM" -t "$IMAGE" .

echo "Warming Lean deps + solc in $RUN_DIR"
docker run --rm \
  --platform "$PLATFORM" \
  -v "$RUN_DIR:/work" \
  -v "$CACHE_DIR:/cache" \
  -w /work \
  "$IMAGE" \
  bash -lc '
    set -euo pipefail
    mkdir -p .lake
    if [[ -d /cache/packages ]]; then
      rm -rf .lake/packages
      cp -a /cache/packages .lake/packages
    fi
    if [[ -f /cache/solidity-import/solc-0.8.34 ]]; then
      mkdir -p .lake/solidity-import
      cp -a /cache/solidity-import/solc-0.8.34 .lake/solidity-import/solc-0.8.34
    fi
    lake exe cache get Mathlib.Tactic
    if [[ ! -x .lake/solidity-import/solc-0.8.34 ]]; then
      python3 .lake/packages/verity/scripts/setup_solc_import.py \
        --output .lake/solidity-import/solc-0.8.34
    fi
    lean-lsp-mcp --version
    rm -rf /cache/packages
    cp -a .lake/packages /cache/packages
    mkdir -p /cache/solidity-import
    cp -a .lake/solidity-import/solc-0.8.34 /cache/solidity-import/solc-0.8.34
    lake build Midnight.Import Midnight.Spec Compiler.SolidityImport.Proofs
  '

echo "Checking lean-lsp MCP on $RUN_DIR"
set +e
docker run --rm \
  --platform "$PLATFORM" \
  -e CURSOR_API_KEY \
  -v "$RUN_DIR:/work" \
  -w /work \
  "$IMAGE" \
  bash -lc 'sh scripts/require-lean-mcp.sh'
MCP_STATUS=$?
set -e
if [[ "$MCP_STATUS" -ne 0 ]]; then
  echo "lean-lsp MCP preflight failed (exit $MCP_STATUS) — run kept at $RUN_DIR"
  exit 2
fi

PROVER_NAME="midnight-prover-$RUN_ID"
MONITOR_NAME="midnight-monitor-$RUN_ID"
PROVER_CURSOR="$RUN_DIR/.prover-cursor"
MONITOR_CURSOR="$MONITOR_DIR/.cursor"
mkdir -p "$PROVER_CURSOR" "$MONITOR_DIR" "$MONITOR_CURSOR"
MONITOR_STARTED=0

cleanup_agents() {
  docker stop "$MONITOR_NAME" >/dev/null 2>&1 || true
  docker rm -f "$MONITOR_NAME" >/dev/null 2>&1 || true
  docker rm -f "$PROVER_NAME" >/dev/null 2>&1 || true
  if [[ -n "${PROVER_LOGS_PID:-}" ]]; then kill "$PROVER_LOGS_PID" >/dev/null 2>&1 || true; fi
  if [[ -n "${MONITOR_LOGS_PID:-}" ]]; then kill "$MONITOR_LOGS_PID" >/dev/null 2>&1 || true; fi
}
trap cleanup_agents EXIT

echo "Starting prover agent on $RUN_DIR (model $AGENT_MODEL, timeout $AGENT_TIMEOUT)"
docker run -d --name "$PROVER_NAME" \
  --platform "$PLATFORM" \
  -e CURSOR_API_KEY \
  -v "$RUN_DIR:/work" \
  -v "$PROVER_CURSOR:/root/.cursor" \
  -w /work \
  "$IMAGE" \
  timeout --signal=TERM --kill-after=30s "$AGENT_TIMEOUT" \
  agent -p --force --trust --approve-mcps --sandbox disabled \
  --model "$AGENT_MODEL" \
  --workspace /work \
  "Prove updatePositionViewProperties. Follow README.md and AGENTS.md. lean-lsp MCP is required — if it is unavailable, write out/mcp-unavailable with a reason and stop immediately (do not continue shell-only). Use lean_diagnostic_messages, lean_goal, lean_hover_info, lean_local_search. Stop when ./check/check_proof.sh exits 0." \
  >/dev/null

docker logs -f "$PROVER_NAME" 2>&1 | while IFS= read -r line; do printf '[prover] %s\n' "$line"; done &
PROVER_LOGS_PID=$!

if [[ "$MONITOR" != "0" ]]; then
  MONITOR_INTERVAL_SECS="$(parse_duration_secs "$MONITOR_INTERVAL")"
  echo "Starting monitor agent (model $MONITOR_MODEL, every $MONITOR_INTERVAL → ${MONITOR_INTERVAL_SECS}s)"
  echo "Monitor media (RW): $MONITOR_DIR — prover workspace mounted read-only at /prover"
  docker run -d --name "$MONITOR_NAME" \
    --platform "$PLATFORM" \
    -e CURSOR_API_KEY \
    -e MONITOR_MODEL="$MONITOR_MODEL" \
    -e MONITOR_INTERVAL_SECS="$MONITOR_INTERVAL_SECS" \
    -e PROVER_ROOT_MOUNT=/prover \
    -e PROVER_CURSOR_MOUNT=/prover-cursor \
    -e MONITOR_DIR_MOUNT=/monitor \
    -v "$MONITOR_DIR:/monitor" \
    -v "$RUN_DIR:/prover:ro" \
    -v "$PROVER_CURSOR:/prover-cursor:ro" \
    -v "$MONITOR_CURSOR:/root/.cursor" \
    -v "$ROOT/scripts/monitor-prover-loop.sh:/monitor-prover-loop.sh:ro" \
    -w /monitor \
    "$IMAGE" \
    bash /monitor-prover-loop.sh \
    >/dev/null
  MONITOR_STARTED=1

  docker logs -f "$MONITOR_NAME" 2>&1 | while IFS= read -r line; do printf '[monitor] %s\n' "$line"; done &
  MONITOR_LOGS_PID=$!
fi

set +e
AGENT_STATUS="$(docker wait "$PROVER_NAME")"
set -e

# Ask the monitor to write its retrospective, then wait for it to finish.
if [[ "$MONITOR_STARTED" -eq 1 ]]; then
  touch "$MONITOR_DIR/stop"
  MONITOR_RETRO_SECS="$(parse_duration_secs "$MONITOR_RETRO_TIMEOUT")"
  echo "Prover finished (status $AGENT_STATUS); waiting up to $MONITOR_RETRO_TIMEOUT (${MONITOR_RETRO_SECS}s) for monitor retrospective"
  set +e
  docker wait "$MONITOR_NAME" >/dev/null &
  MONITOR_WAIT_PID=$!
  elapsed=0
  while kill -0 "$MONITOR_WAIT_PID" >/dev/null 2>&1; do
    if (( elapsed >= MONITOR_RETRO_SECS )); then
      echo "Monitor retrospective timed out after $MONITOR_RETRO_TIMEOUT — stopping monitor"
      docker stop "$MONITOR_NAME" >/dev/null 2>&1 || true
      break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  wait "$MONITOR_WAIT_PID" 2>/dev/null
  set -e
fi

sleep 1
if [[ -n "${MONITOR_LOGS_PID:-}" ]]; then kill "$MONITOR_LOGS_PID" >/dev/null 2>&1 || true; fi
if [[ -n "${PROVER_LOGS_PID:-}" ]]; then kill "$PROVER_LOGS_PID" >/dev/null 2>&1 || true; fi
docker rm -f "$MONITOR_NAME" >/dev/null 2>&1 || true
docker rm -f "$PROVER_NAME" >/dev/null 2>&1 || true
trap - EXIT

if [[ -f "$MONITOR_DIR/retrospective.md" ]]; then
  echo "======== monitor retrospective ========"
  cat "$MONITOR_DIR/retrospective.md"
  echo "======== end retrospective (also at $MONITOR_DIR/) ========"
elif [[ "$MONITOR_STARTED" -eq 1 ]]; then
  echo "Monitor retrospective missing — see $MONITOR_DIR/journal.md" >&2
fi

if [[ -f "$RUN_DIR/out/mcp-unavailable" ]]; then
  echo "Agent reported lean-lsp MCP unavailable — run kept at $RUN_DIR"
  cat "$RUN_DIR/out/mcp-unavailable" >&2 || true
  exit 91
fi
if [[ "$AGENT_STATUS" -eq 124 ]]; then
  echo "Agent timed out after $AGENT_TIMEOUT — run kept at $RUN_DIR"
  exit 124
elif [[ "$AGENT_STATUS" -ne 0 ]]; then
  echo "Agent exited with status $AGENT_STATUS — run kept at $RUN_DIR"
  exit "$AGENT_STATUS"
fi

echo "Checking proof"
if docker run --rm \
  --platform "$PLATFORM" \
  -v "$RUN_DIR:/work" \
  -w /work \
  "$IMAGE" \
  bash -lc './check/check_proof.sh'
then
  mkdir -p "$RESULT_DIR"
  cp -a "$RUN_DIR/Midnight" "$RESULT_DIR/"
  cp -a "$RUN_DIR/out" "$RESULT_DIR/" 2>/dev/null || true
  # Copy monitor artifacts only — skip .cursor (contains unix sockets cp can't copy).
  if [[ -d "$MONITOR_DIR" ]]; then
    mkdir -p "$RESULT_DIR/monitor"
    for f in journal.md retrospective.md; do
      if [[ -f "$MONITOR_DIR/$f" ]]; then
        cp "$MONITOR_DIR/$f" "$RESULT_DIR/monitor/"
      fi
    done
  fi

  printf '%s\n' "$RUN_ID" > "$RESULT_DIR/RUN_ID"
  echo "SUCCESS — proof saved to $RESULT_DIR"
  echo "Run directory kept at $RUN_DIR"
  echo "Monitor logs kept at $MONITOR_DIR"
  exit 0
else
  echo "FAILED — proof not extracted. Inspect $RUN_DIR (monitor: $MONITOR_DIR)"
  exit 1
fi
