#!/bin/bash
# Browser subscription login in Linux, where Claude stores a portable cache.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/platform.sh
CLAUDE_AUTH_DIR="${CLAUDE_AUTH_DIR:-$PWD/.auth/claude}"
mkdir -p "$CLAUDE_AUTH_DIR"
chmod 700 "$CLAUDE_AUTH_DIR"
docker build --platform "$PLATFORM" -t "${IMAGE:-midnight-agent}" .
docker run --rm -it --platform "$PLATFORM" \
  -e CLAUDE_CONFIG_DIR=/root/.claude \
  -e CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  -e DISABLE_AUTOUPDATER=1 \
  -v "$CLAUDE_AUTH_DIR:/root/.claude" \
  -w /tmp "${IMAGE:-midnight-agent}" claude auth login --claudeai
python3 scripts/claude-auth.py "$CLAUDE_AUTH_DIR/.credentials.json"
