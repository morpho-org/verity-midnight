# Sourced by the host launchers. Credentials are passed by name, never by value.
AGENT_BACKEND="${AGENT_BACKEND:-cursor}"
case "$AGENT_BACKEND" in
  cursor)
    AGENT_KEY_ENV=CURSOR_API_KEY
    AGENT_HOME_MOUNT=/root/.cursor
    AGENT_MODEL="${AGENT_MODEL:-gpt-5.6-sol-high}"
    # Cursor's API hosts are not documented; add hosts with EGRESS_ALLOW_EXTRA if the
    # proxy log (audit-logs/<id>/tinyproxy.log) shows a refused Cursor host.
    EGRESS_ALLOW_DEFAULT='(^|\.)cursor\.sh$ ^(api\.)?cursor\.com$'
    ;;
  codex)
    AGENT_KEY_ENV=CODEX_API_KEY
    AGENT_HOME_MOUNT=/root/.codex
    AGENT_MODEL="${AGENT_MODEL:-gpt-6.1-sol}"
    CODEX_AUTH="${CODEX_AUTH:-api-key}"
    case "$CODEX_AUTH" in
      api-key|chatgpt) ;;
      *) echo "Invalid CODEX_AUTH: $CODEX_AUTH (expected api-key or chatgpt)" >&2; exit 2 ;;
    esac
    CODEX_AUTH_FILE="${CODEX_AUTH_FILE:-${CODEX_HOME:-$HOME/.codex}/auth.json}"
    # API key (api.openai.com) and ChatGPT sign-in (chatgpt.com, auth.openai.com).
    EGRESS_ALLOW_DEFAULT='^api\.openai\.com$ ^chatgpt\.com$ ^auth\.openai\.com$'
    ;;
  claude)
    AGENT_HOME_MOUNT=/root/.claude
    AGENT_MODEL="${AGENT_MODEL:-opus}"
    CLAUDE_AUTH="${CLAUDE_AUTH:-api-key}"
    case "$CLAUDE_AUTH" in
      api-key) AGENT_KEY_ENV=ANTHROPIC_API_KEY ;;
      oauth) AGENT_KEY_ENV=CLAUDE_CODE_OAUTH_TOKEN ;;
      login) AGENT_KEY_ENV=CLAUDE_CODE_OAUTH_TOKEN ;;
      *) echo "Invalid CLAUDE_AUTH: $CLAUDE_AUTH (expected api-key, oauth or login)" >&2; exit 2 ;;
    esac
    CLAUDE_AUTH_FILE="${CLAUDE_AUTH_FILE:-$PWD/.auth/claude/.credentials.json}"
    EGRESS_ALLOW_DEFAULT='^api\.anthropic\.com$ ^claude\.ai$ ^platform\.claude\.com$'
    ;;
  *)
    echo "Unknown AGENT_BACKEND: $AGENT_BACKEND (expected cursor, codex or claude)" >&2
    exit 2
    ;;
esac
# Forward only the selected credential. ChatGPT uses a cached login instead.
AGENT_AUTH_ARGS="-e $AGENT_KEY_ENV"
if [[ "$AGENT_BACKEND" == codex && "$CODEX_AUTH" == chatgpt ]]; then
  AGENT_AUTH_ARGS=""
fi
if [[ "$AGENT_BACKEND" == claude && "$CLAUDE_AUTH" == login ]]; then
  AGENT_AUTH_ARGS=""
fi
# Space-separated extended regexes (matched on the host name) for the hosts
# agent containers may reach through the egress proxy.
EGRESS_ALLOW="$EGRESS_ALLOW_DEFAULT ${EGRESS_ALLOW_EXTRA:-}"
AGENT_REASONING_EFFORT="${AGENT_REASONING_EFFORT:-high}"
MONITOR_REASONING_EFFORT="${MONITOR_REASONING_EFFORT:-$AGENT_REASONING_EFFORT}"
if [[ "$AGENT_BACKEND" == claude ]]; then
  for effort in "$AGENT_REASONING_EFFORT" "$MONITOR_REASONING_EFFORT"; do
    case "$effort" in
      low|medium|high|xhigh|max) ;;
      *) echo "Invalid Claude reasoning effort: $effort" >&2; exit 2 ;;
    esac
  done
fi
if [[ "$AGENT_BACKEND" == codex ]]; then
  for effort in "$AGENT_REASONING_EFFORT" "$MONITOR_REASONING_EFFORT"; do
    case "$effort" in
      none|minimal|low|medium|high|xhigh|max) ;;
      *) echo "Invalid Codex reasoning effort: $effort" >&2; exit 2 ;;
    esac
  done
fi
