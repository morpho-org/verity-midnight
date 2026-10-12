#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export LEAN_PROJECT_PATH="$PWD"
export LEAN_LOG_LEVEL=NONE
# Image install (Dockerfile) preferred; checkout-local venv as fallback.
if [ -x /opt/lean-mcp/bin/lean-lsp-mcp ]; then
  exec /opt/lean-mcp/bin/lean-lsp-mcp "$@"
fi
exec .lake/lean-mcp/bin/lean-lsp-mcp "$@"
