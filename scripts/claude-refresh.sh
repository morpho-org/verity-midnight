#!/bin/bash
# Refresh a Claude subscription login once, on the host side, so every agent
# container starts with the same fresh access token and none of them has to
# refresh it. (Refreshing rotates the refresh token: an agent that refreshed
# would invalidate the copies held by the others and by the host cache.)
#
#   claude-refresh.sh CREDENTIALS_FILE MIN_LIFETIME_SECS
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/platform.sh
file="$1"
min_lifetime="$2"
tmp="$(mktemp -d "$(dirname "$file")/refresh.XXXXXX")"
trap '[[ -n "$tmp" && -d "$tmp" ]] && rm -r -- "$tmp"' EXIT
cp "$file" "$tmp/.credentials.json"
chmod 600 "$tmp/.credentials.json"
# Mark the access token expired so the CLI refreshes it at startup.
python3 - "$tmp/.credentials.json" <<'PY'
import json, sys, time
path = sys.argv[1]
auth = json.load(open(path))
auth["claudeAiOauth"]["expiresAt"] = int((time.time() - 60) * 1000)
json.dump(auth, open(path, "w"))
PY
echo "Refreshing the Claude login (one minimal Haiku request)"
# The prompt goes on stdin: --mcp-config and --tools take several values and
# would otherwise swallow a trailing prompt argument.
printf 'Reply with the single word OK.' | docker run --rm -i --platform "$PLATFORM" \
  -v "$tmp:/root/.claude" \
  -e CLAUDE_CONFIG_DIR=/root/.claude \
  -e CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  -e DISABLE_AUTOUPDATER=1 \
  "${IMAGE:-midnight-agent}" \
  claude -p --model haiku --tools '' --setting-sources '' \
    --strict-mcp-config --mcp-config '{"mcpServers":{}}' >/dev/null
python3 scripts/claude-auth.py "$tmp/.credentials.json" >/dev/null
if ! python3 scripts/claude-auth.py --min-lifetime "$min_lifetime" "$tmp/.credentials.json"; then
  echo "WARNING: even a fresh Claude token expires before the run ends; an agent will" \
    "have to refresh it, which can log the other agent out" >&2
fi
# Replace the cache atomically: its old refresh token is no longer valid.
mv "$tmp/.credentials.json" "$file"
chmod 600 "$file"
echo "Claude login refreshed in $file"
