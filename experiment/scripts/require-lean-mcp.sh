#!/bin/sh
# Exit 0 if lean-lsp MCP is usable; otherwise print a reason and exit 2.
set -eu
cd "$(dirname "$0")/.."

if ! command -v agent >/dev/null 2>&1; then
  echo "require-lean-mcp: agent CLI not found" >&2
  exit 2
fi
if ! sh scripts/lean-mcp.sh --version >/dev/null 2>&1; then
  echo "require-lean-mcp: lean-mcp.sh failed" >&2
  exit 2
fi

agent mcp enable lean-lsp >/dev/null
status="$(agent mcp list 2>&1 || true)"
echo "$status"
case "$status" in
  *'lean-lsp: ready'*) ;;
  *)
    echo "require-lean-mcp: lean-lsp is not ready" >&2
    exit 2
    ;;
esac

if ! agent mcp list-tools lean-lsp 2>/dev/null | grep -q lean_diagnostic_messages; then
  echo "require-lean-mcp: lean_diagnostic_messages tool missing" >&2
  exit 2
fi

echo "require-lean-mcp: lean-lsp MCP ok"
