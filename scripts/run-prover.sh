#!/bin/bash
# Runs inside the isolated Docker container. Docker supplies the sandbox.
set -euo pipefail

PROMPT="Prove updatePositionViewProperties. Follow README.md and AGENTS.md. lean-lsp MCP is required — if it is unavailable, write out/mcp-unavailable with a reason and stop immediately (do not continue shell-only). Use lean_diagnostic_messages, lean_goal, lean_hover_info, lean_local_search. Stop when ./check/check_proof.sh exits 0."

case "${AGENT_BACKEND:-cursor}" in
  cursor)
    exec agent -p --force --trust --approve-mcps --sandbox disabled \
      --model "${AGENT_MODEL:?}" --workspace /work "$PROMPT"
    ;;
  codex)
    codex exec --cd /work --skip-git-repo-check \
      --dangerously-bypass-approvals-and-sandbox \
      --model "${AGENT_MODEL:?}" \
      -c "model_reasoning_effort=\"${AGENT_REASONING_EFFORT:-high}\"" \
      --json "$PROMPT" | tee /root/.codex/prover-events.jsonl
    ;;
  *) echo "Unknown AGENT_BACKEND: $AGENT_BACKEND" >&2; exit 2 ;;
esac
