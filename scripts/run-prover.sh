#!/bin/bash
# Runs inside the isolated Docker container. Docker supplies the sandbox.
set -euo pipefail

PROMPT="Prove the theorem requested in README.md. Follow README.md and AGENTS.md. lean-lsp MCP is required — if it is unavailable, write out/mcp-unavailable with a reason and stop immediately (do not continue shell-only). Use lean_diagnostic_messages, lean_goal, lean_hover_info, lean_local_search. Stop when ./check/check_proof.sh exits 0."

if [[ "${TURBO_LEAN:-0}" =~ ^(1|force|hard)$ ]]; then
  export PATH="/opt/turbo-lean/bin:$PATH"
  export TURBO_LEAN_MAX_IDLE_ZYGOTES="${TURBO_LEAN_MAX_IDLE_ZYGOTES:-2}"
  export TURBO_LEAN_MAX_ZYGOTE_PROCESSES="${TURBO_LEAN_MAX_ZYGOTE_PROCESSES:-3}"
  if [[ -z "${TURBO_LEAN_SKIP_WARMUP:-}" && -d .lake ]]; then
    case "${EXPERIMENT_TASK:-update-position-view}" in
      wexp) WARM_SMOKE="Midnight/Proof.lean" ;;
      wexp-positive) WARM_SMOKE="check/TickLibPositiveSmoke.lean" ;;
      wexp-original) WARM_SMOKE="check/TickLibImportSmoke.lean" ;;
      ticklib) WARM_SMOKE="check/TickLibFullSmoke.lean" ;;
      *) WARM_SMOKE="check/UpdatePositionViewSmoke.lean" ;;
    esac
    for warm_target in "$WARM_SMOKE" "Midnight/Proof.lean"; do
      if [[ -f "$warm_target" ]]; then
        LEAN_MEMORY_MB=0 turbo-lean check "$warm_target" --project-dir . >/dev/null 2>&1 || true
      fi
    done
  fi
fi

if [[ "${TURBO_LEAN:-0}" == "1" ]]; then
  PROMPT="$PROMPT turbo-lean is installed for fast single-declaration checks: while iterating on a lemma or theorem, run \`turbo-lean check <File.lean> --decl <name> --project-dir .\` instead of \`lake build\`, \`lake env lean\`, or \`leanrun <File.lean>\` (prefer \`--decl <name>\` over whole-file \`turbo-lean check <File.lean>\` while the file still has broken or \`sorry\` declarations). Run \`lake build <Module>\` only when a module that other files import has changed. lean-lsp MCP is still required for goals, diagnostics and search, and ./check/check_proof.sh is still the final judge."
elif [[ "${TURBO_LEAN:-0}" == "force" ]]; then
  PROMPT="$PROMPT In this trial \`lake build\`, \`lake env lean\`, and \`leanrun <File.lean>\` are blocked for you. To check edits, run \`turbo-lean check <File.lean> --decl <name> --project-dir .\` for the specific declaration you are editing (prefer \`--decl <name>\` over whole-file \`turbo-lean check <File.lean>\` while the file still has broken or \`sorry\` declarations). After changing a module that other files import, run \`turbo-lean build <Module> --project-dir .\` (for example \`turbo-lean build Midnight.Lemmas.Foo --project-dir .\`, not an unscoped \`turbo-lean build\`) before checking files that import it. lean-lsp MCP is still required for goals, diagnostics and search, and ./check/check_proof.sh (allowed) is still the final judge."
elif [[ "${TURBO_LEAN:-0}" == "hard" ]]; then
  PROMPT="Prove the theorem requested in README.md. Follow README.md and AGENTS.md, except its lean-lsp MCP requirement: this trial has no MCP on purpose — do not write out/mcp-unavailable. Shell Lean is disabled too: \`lake\`, \`lean\`, \`leanrun\`, \`elan\` and \`./check/check_proof.sh\` are blocked for you. The only compiler feedback available is \`turbo-lean check <File.lean> --decl <name> --project-dir .\` — it reports errors per declaration but no goal states — and \`turbo-lean build <Module> --project-dir .\`, which you must run after changing a module that other files import (for example \`turbo-lean build Midnight.Lemmas.Foo --project-dir .\`, not an unscoped \`turbo-lean build\`). The proof must not use \`sorry\` or \`admit\`; after you stop, the host runs the full checker and an axiom audit. Stop when \`turbo-lean check Midnight/Proof.lean --project-dir .\` verifies the whole file."
fi

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
  claude)
    source /opt/midnight/claude-common.sh
    MCP_CFG=/opt/midnight/claude-prover.json
    if [[ "${TURBO_LEAN:-0}" == "hard" ]]; then
      MCP_CFG='{"mcpServers":{}}'
    fi
    run_claude --model "${AGENT_MODEL:?}" \
      --effort "${AGENT_REASONING_EFFORT:-high}" \
      --mcp-config "$MCP_CFG" \
      --verbose --output-format stream-json "$PROMPT" \
      | tee /root/.claude/prover-events.jsonl
    ;;
  *) echo "Unknown AGENT_BACKEND: $AGENT_BACKEND" >&2; exit 2 ;;
esac
