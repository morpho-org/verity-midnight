#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export LEAN_PROJECT_PATH="$PWD"
export LEAN_LOG_LEVEL=NONE
# At most two open file workers (each can hold about 2 GB), so they leave
# memory for `lake build`. Elaborating Proof.lean at startup loads the task's
# imports and the symbol index before the agent's first search.
export LEAN_LSP_MAX_OPEN_FILES="${LEAN_LSP_MAX_OPEN_FILES:-2}"
export LEAN_MCP_PREWARM_FILES="${LEAN_MCP_PREWARM_FILES:-Midnight/Proof.lean}"
# Image install (Dockerfile) preferred; checkout-local venv as fallback.
if [ -x /opt/lean-mcp/bin/lean-lsp-mcp ]; then
  exec /opt/lean-mcp/bin/lean-lsp-mcp "$@"
fi
exec .lake/lean-mcp/bin/lean-lsp-mcp "$@"
