# Sourced by the host launchers. Credentials are passed by name, never by value.
AGENT_BACKEND="${AGENT_BACKEND:-cursor}"
case "$AGENT_BACKEND" in
  cursor)
    AGENT_KEY_ENV=CURSOR_API_KEY
    AGENT_HOME_MOUNT=/root/.cursor
    AGENT_MODEL="${AGENT_MODEL:-gpt-5.6-sol-high}"
    ;;
  codex)
    AGENT_KEY_ENV=CODEX_API_KEY
    AGENT_HOME_MOUNT=/root/.codex
    AGENT_MODEL="${AGENT_MODEL:-gpt-6.1-sol}"
    ;;
  *)
    echo "Unknown AGENT_BACKEND: $AGENT_BACKEND (expected cursor or codex)" >&2
    exit 2
    ;;
esac
AGENT_REASONING_EFFORT="${AGENT_REASONING_EFFORT:-high}"
MONITOR_REASONING_EFFORT="${MONITOR_REASONING_EFFORT:-$AGENT_REASONING_EFFORT}"
if [[ "$AGENT_BACKEND" == codex ]]; then
  for effort in "$AGENT_REASONING_EFFORT" "$MONITOR_REASONING_EFFORT"; do
    case "$effort" in
      none|minimal|low|medium|high|xhigh|max) ;;
      *) echo "Invalid Codex reasoning effort: $effort" >&2; exit 2 ;;
    esac
  done
fi
