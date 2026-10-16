#!/bin/bash
# Fresh trial each invocation: copy experiment/ → runs/<id>/, run agent there,
# and on success extract the proof to results/<id>/. Next run never sees prior proofs.
set -euo pipefail

cd "$(dirname "$0")"
source scripts/agent-backend.sh
if [[ "$AGENT_BACKEND" == codex && "$CODEX_AUTH" == chatgpt ]]; then
  python3 scripts/codex-auth.py "$CODEX_AUTH_FILE"
elif [[ "$AGENT_BACKEND" == claude && "$CLAUDE_AUTH" == login ]]; then
  python3 scripts/claude-auth.py "$CLAUDE_AUTH_FILE"
elif [[ -z "${!AGENT_KEY_ENV:-}" ]]; then
  echo "$AGENT_KEY_ENV must be set for AGENT_BACKEND=$AGENT_BACKEND" >&2
  exit 2
fi

source scripts/platform.sh
IMAGE="${IMAGE:-midnight-agent}"
AGENT_TIMEOUT="${AGENT_TIMEOUT:-120m}"
# Per-process memory cap (MB) for Lean in the prover container; 0 disables it.
# Warm-up and the final checker run without the cap.
LEAN_MEMORY_MB="${LEAN_MEMORY_MB:-6144}"
EXPERIMENT_TASK="${EXPERIMENT_TASK:-update-position-view}"
case "$EXPERIMENT_TASK" in
  update-position-view|wexp|wexp-positive|wexp-original|ticklib) ;;
  *) echo "Unknown EXPERIMENT_TASK: $EXPERIMENT_TASK" >&2; exit 2 ;;
esac
# Second agent using the same backend, journaling progress and a retrospective.
MONITOR="${MONITOR:-1}"
MONITOR_MODEL="${MONITOR_MODEL:-$AGENT_MODEL}"
MONITOR_INTERVAL="${MONITOR_INTERVAL:-2m}"
# How long to wait for the monitor's final retrospective after the prover stops.
MONITOR_RETRO_TIMEOUT="${MONITOR_RETRO_TIMEOUT:-20m}"
# Route agent containers through an allowlisting proxy so they can reach the
# model API but not GitHub or anywhere else a published proof could be found.
EGRESS="${EGRESS:-1}"
RUN_ID="$(date +%Y%m%d-%H%M%S)-$AGENT_BACKEND"
if [[ "$EXPERIMENT_TASK" != update-position-view ]]; then
  RUN_ID="$RUN_ID-$EXPERIMENT_TASK"
fi
TEMPLATE="$PWD/experiment"
RUN_DIR="$PWD/runs/$RUN_ID"
# Monitor state is outside the prover workspace so the prover cannot see or
# be affected by journal / retrospective writes.
MONITOR_DIR="$PWD/monitor-logs/$RUN_ID"
RESULT_DIR="$PWD/results/$RUN_ID"
# Egress proxy log and transcript audit; outside the prover workspace.
AUDIT_DIR="$PWD/audit-logs/$RUN_ID"
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

mkdir -p "$PWD/runs" "$PWD/results" "$PWD/monitor-logs" "$PWD/audit-logs" "$CACHE_DIR"

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
if [[ "$EXPERIMENT_TASK" == wexp ]]; then
  python3 scripts/prepare-wexp-task.py "$RUN_DIR"
  python3 "$RUN_DIR/check/check_frozen.py" --start
elif [[ "$EXPERIMENT_TASK" == wexp-positive ]]; then
  python3 scripts/prepare-wexp-positive-task.py "$RUN_DIR"
  python3 "$RUN_DIR/check/check_frozen.py" --start
elif [[ "$EXPERIMENT_TASK" == wexp-original ]]; then
  python3 scripts/prepare-wexp-original-task.py "$RUN_DIR"
  python3 "$RUN_DIR/check/check_frozen.py" --start
elif [[ "$EXPERIMENT_TASK" == ticklib ]]; then
  python3 scripts/prepare-ticklib-task.py "$RUN_DIR"
  python3 "$RUN_DIR/check/check_frozen.py" --start
fi

docker build --platform "$PLATFORM" -t "$IMAGE" .

echo "Warming Lean deps + solc in $RUN_DIR"
docker run --rm \
  --platform "$PLATFORM" \
  -v "$RUN_DIR:/work" \
  -v "$CACHE_DIR:/cache" \
  -e EXPERIMENT_TASK="$EXPERIMENT_TASK" \
  -e LEAN_MEMORY_MB=0 \
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
    # The linux-amd64 solc on every platform (the only Linux build the importer
    # accepts); on linux/arm64 it runs under amd64 emulation.
    python3 /opt/midnight/install-solc.py .lake/packages/verity/scripts/setup_solc_import.py \
      .lake/solidity-import/solc-0.8.34
    lean-lsp-mcp --version
    rm -rf /cache/packages
    cp -a .lake/packages /cache/packages
    mkdir -p /cache/solidity-import
    cp -a .lake/solidity-import/solc-0.8.34 /cache/solidity-import/solc-0.8.34
    if [[ "$EXPERIMENT_TASK" == wexp ]]; then
      lake build Midnight.TickLibSpec
    elif [[ "$EXPERIMENT_TASK" == wexp-positive ]]; then
      lake build Midnight.TickLibPositiveSpec Compiler.SolidityImport.Proofs ProofKit
      lake env lean check/TickLibPositiveSmoke.lean
    elif [[ "$EXPERIMENT_TASK" == wexp-original ]]; then
      lake build Midnight.TickLibImportSpec ProofKit
      lake env lean check/TickLibImportSmoke.lean
    elif [[ "$EXPERIMENT_TASK" == ticklib ]]; then
      lake build Midnight.TickLibFullSpec ProofKit
      lake env lean check/TickLibFullSmoke.lean
    else
      lake build Midnight.Import Midnight.Spec Compiler.SolidityImport.Proofs ProofKit
      lake env lean check/UpdatePositionViewSmoke.lean
    fi
  '

echo "Checking lean-lsp MCP on $RUN_DIR"
set +e
docker run --rm \
  --platform "$PLATFORM" \
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
PROXY_NAME="midnight-egress-$RUN_ID"
EGRESS_NET="midnight-egress-$RUN_ID"
mkdir -p "$AUDIT_DIR"

cleanup_egress() {
  docker rm -f "$PROXY_NAME" >/dev/null 2>&1 || true
  docker network rm "$EGRESS_NET" >/dev/null 2>&1 || true
}

# Docker arguments that put an agent container behind the egress proxy.
# Kept as a string because empty arrays break `set -u` on macOS bash 3.2.
AGENT_NET_ARGS=""
if [[ "$EGRESS" != "0" ]]; then
  echo "Starting egress proxy (allowing: $EGRESS_ALLOW)"
  # tinyproxy runs as nobody and must be able to write its log here.
  chmod 777 "$AUDIT_DIR"
  tr ' ' '\n' <<<"$EGRESS_ALLOW" | sed '/^$/d' >"$AUDIT_DIR/allow"
  # --internal: containers on this network have no route out except the proxy,
  # which is also attached to the default bridge.
  docker network create --internal "$EGRESS_NET" >/dev/null
  docker run -d --name "$PROXY_NAME" \
    --platform "$PLATFORM" \
    -v "$AUDIT_DIR:/egress" \
    "$IMAGE" \
    tinyproxy -d -c /opt/midnight/tinyproxy.conf \
    >/dev/null
  docker network connect --alias egress-proxy "$EGRESS_NET" "$PROXY_NAME"
  PROXY_URL=http://egress-proxy:8888
  AGENT_NET_ARGS="--network $EGRESS_NET \
    -e HTTPS_PROXY=$PROXY_URL -e https_proxy=$PROXY_URL \
    -e HTTP_PROXY=$PROXY_URL -e http_proxy=$PROXY_URL \
    -e NO_PROXY=localhost,127.0.0.1 -e no_proxy=localhost,127.0.0.1 \
    -e NODE_USE_ENV_PROXY=1"

  # Fail closed: refuse to start the agent if GitHub is reachable either
  # through the proxy or directly.
  set +e
  # shellcheck disable=SC2086
  docker run --rm --platform "$PLATFORM" $AGENT_NET_ARGS "$IMAGE" bash -c '
    sleep 1
    if curl -sS -o /dev/null --max-time 15 https://github.com/ 2>/dev/null; then
      echo "github.com is reachable through the egress proxy" >&2; exit 1
    fi
    if curl -sS -o /dev/null --max-time 15 --noproxy "*" https://github.com/ 2>/dev/null; then
      echo "github.com is reachable without the proxy" >&2; exit 1
    fi
  '
  EGRESS_STATUS=$?
  set -e
  if [[ "$EGRESS_STATUS" -ne 0 ]]; then
    echo "Egress preflight failed — agent not started (run kept at $RUN_DIR)"
    cleanup_egress
    exit 2
  fi
else
  echo "WARNING: EGRESS=0 — agents have unrestricted network access, including to published proofs"
fi
PROVER_HOME="$RUN_DIR/.prover-$AGENT_BACKEND"
MONITOR_HOME="$MONITOR_DIR/.$AGENT_BACKEND"
mkdir -p "$PROVER_HOME" "$MONITOR_DIR" "$MONITOR_HOME"
if [[ "$AGENT_BACKEND" == codex ]]; then
  cp "$ROOT/scripts/codex-prover.toml" "$PROVER_HOME/config.toml"
  if [[ "$CODEX_AUTH" == chatgpt ]]; then
    python3 scripts/codex-auth.py "$CODEX_AUTH_FILE" "$PROVER_HOME" "$MONITOR_HOME"
  fi
elif [[ "$AGENT_BACKEND" == claude && "$CLAUDE_AUTH" == login ]]; then
  # Both agents get copies of one login. Make sure its access token outlives the
  # run, so neither agent refreshes it: a refresh rotates the refresh token and
  # logs out the other agent (and the host cache).
  AUTH_LIFETIME_SECS=$(( $(parse_duration_secs "$AGENT_TIMEOUT") \
    + $(parse_duration_secs "$MONITOR_RETRO_TIMEOUT") + 900 ))
  if ! python3 scripts/claude-auth.py --min-lifetime "$AUTH_LIFETIME_SECS" "$CLAUDE_AUTH_FILE"; then
    PLATFORM="$PLATFORM" IMAGE="$IMAGE" bash scripts/claude-refresh.sh \
      "$CLAUDE_AUTH_FILE" "$AUTH_LIFETIME_SECS"
  fi
  python3 scripts/claude-auth.py "$CLAUDE_AUTH_FILE" "$PROVER_HOME" "$MONITOR_HOME"
fi
MONITOR_STARTED=0

cleanup_agents() {
  docker stop "$MONITOR_NAME" >/dev/null 2>&1 || true
  docker rm -f "$MONITOR_NAME" >/dev/null 2>&1 || true
  docker rm -f "$PROVER_NAME" >/dev/null 2>&1 || true
  if [[ -n "${PROVER_LOGS_PID:-}" ]]; then kill "$PROVER_LOGS_PID" >/dev/null 2>&1 || true; fi
  if [[ -n "${MONITOR_LOGS_PID:-}" ]]; then kill "$MONITOR_LOGS_PID" >/dev/null 2>&1 || true; fi
  cleanup_egress
}
trap cleanup_agents EXIT

# Files outside the agent's edit area (Midnight/), to flag leftovers afterwards.
workspace_files() {
  (cd "$RUN_DIR" && find . \( -path ./.lake -o -path "./.prover-*" -o -path ./out \
    -o -path ./Midnight -o -name __pycache__ \) -prune -o -type f -print | sort)
}
workspace_files >"$AUDIT_DIR/files-before.txt"

echo "Starting $AGENT_BACKEND prover on $RUN_DIR (model $AGENT_MODEL, timeout $AGENT_TIMEOUT)"
# shellcheck disable=SC2086
docker run -d --name "$PROVER_NAME" \
  --platform "$PLATFORM" \
  $AGENT_NET_ARGS \
  $AGENT_AUTH_ARGS \
  -e AGENT_BACKEND="$AGENT_BACKEND" \
  -e AGENT_MODEL="$AGENT_MODEL" \
  -e AGENT_REASONING_EFFORT="$AGENT_REASONING_EFFORT" \
  -e LEAN_MEMORY_MB="$LEAN_MEMORY_MB" \
  -v "$RUN_DIR:/work" \
  -v "$PROVER_HOME:$AGENT_HOME_MOUNT" \
  -w /work \
  "$IMAGE" \
  timeout --signal=TERM --kill-after=30s "$AGENT_TIMEOUT" \
  bash /opt/midnight/run-prover.sh \
  >/dev/null

docker logs -f "$PROVER_NAME" 2>&1 | while IFS= read -r line; do printf '[prover] %s\n' "$line"; done &
PROVER_LOGS_PID=$!

if [[ "$MONITOR" != "0" ]]; then
  MONITOR_INTERVAL_SECS="$(parse_duration_secs "$MONITOR_INTERVAL")"
  echo "Starting monitor agent (model $MONITOR_MODEL, every $MONITOR_INTERVAL → ${MONITOR_INTERVAL_SECS}s)"
  echo "Monitor media (RW): $MONITOR_DIR — prover workspace mounted read-only at /prover"
  # shellcheck disable=SC2086
  docker run -d --name "$MONITOR_NAME" \
    --platform "$PLATFORM" \
    $AGENT_NET_ARGS \
    $AGENT_AUTH_ARGS \
    -e AGENT_BACKEND="$AGENT_BACKEND" \
    -e MONITOR_REASONING_EFFORT="$MONITOR_REASONING_EFFORT" \
    -e MONITOR_MODEL="$MONITOR_MODEL" \
    -e MONITOR_INTERVAL_SECS="$MONITOR_INTERVAL_SECS" \
    -e PROVER_ROOT_MOUNT=/prover \
    -e PROVER_HOME_MOUNT=/prover-agent-home \
    -e MONITOR_DIR_MOUNT=/monitor \
    -v "$MONITOR_DIR:/monitor" \
    -v "$RUN_DIR:/prover:ro" \
    -v "$PROVER_HOME:/prover-agent-home:ro" \
    -v "$MONITOR_HOME:$AGENT_HOME_MOUNT" \
    -w /monitor \
    "$IMAGE" \
    bash /opt/midnight/monitor-prover-loop.sh \
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
cleanup_egress
trap - EXIT

workspace_files >"$AUDIT_DIR/files-after.txt"
comm -13 "$AUDIT_DIR/files-before.txt" "$AUDIT_DIR/files-after.txt" >"$AUDIT_DIR/stray-files.txt"
if [[ -s "$AUDIT_DIR/stray-files.txt" ]]; then
  echo "WARNING: the prover left files outside Midnight/ (see $AUDIT_DIR/stray-files.txt):"
  sed 's/^/  /' "$AUDIT_DIR/stray-files.txt"
fi

echo "Auditing prover transcripts"
AUDIT_ARGS=(--backend "$AGENT_BACKEND" --prover-home "$PROVER_HOME" --out "$AUDIT_DIR/audit.md")
if [[ "$EGRESS" != "0" ]]; then
  AUDIT_ARGS+=(--proxy-log "$AUDIT_DIR/tinyproxy.log")
fi
set +e
python3 scripts/audit_transcripts.py "${AUDIT_ARGS[@]}"
AUDIT_STATUS=$?
set -e

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

if [[ "$AUDIT_STATUS" -ne 0 ]]; then
  echo "Audit flagged a possible answer lookup — proof not checked or extracted."
  echo "Review $AUDIT_DIR/audit.md (run kept at $RUN_DIR)"
  exit 92
fi

echo "Checking proof"
if docker run --rm \
  --platform "$PLATFORM" \
  --network none \
  -e LEAN_MEMORY_MB=0 \
  -v "$RUN_DIR:/work" \
  -w /work \
  "$IMAGE" \
  bash -lc './check/check_proof.sh'
then
  mkdir -p "$RESULT_DIR"
  cp -a "$RUN_DIR/Midnight" "$RESULT_DIR/"
  if [[ "$EXPERIMENT_TASK" == wexp-positive ]]; then
    cp -a "$RUN_DIR/solidity" "$RESULT_DIR/"
  fi
  cp -a "$RUN_DIR/out" "$RESULT_DIR/" 2>/dev/null || true
  # Copy monitor artifacts only, excluding backend session storage.
  if [[ -d "$MONITOR_DIR" ]]; then
    mkdir -p "$RESULT_DIR/monitor"
    for f in journal.md retrospective.md; do
      if [[ -f "$MONITOR_DIR/$f" ]]; then
        cp "$MONITOR_DIR/$f" "$RESULT_DIR/monitor/"
      fi
    done
  fi

  cp "$AUDIT_DIR/audit.md" "$RESULT_DIR/"
  printf '%s\n' "$RUN_ID" > "$RESULT_DIR/RUN_ID"
  echo "SUCCESS — proof saved to $RESULT_DIR"
  echo "Run directory kept at $RUN_DIR"
  echo "Monitor logs kept at $MONITOR_DIR"
  exit 0
else
  echo "FAILED — proof not extracted. Inspect $RUN_DIR (monitor: $MONITOR_DIR)"
  exit 1
fi
