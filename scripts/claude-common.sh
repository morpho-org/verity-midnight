# Sourced inside Docker by both Claude entry points.
export CLAUDE_CONFIG_DIR=/root/.claude
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export ENABLE_CLAUDEAI_MCP_SERVERS=false
export DISABLE_AUTOUPDATER=1
export MCP_TIMEOUT=60000

run_claude() {
  # Explicit approvals work as root; bypassPermissions requires a non-root user.
  # Docker and the egress proxy supply isolation. Keep hosted web tools absent.
  # Do not use --bare: it ignores subscription OAuth tokens.
  claude -p --permission-mode dontAsk \
    --tools 'Bash,Read,Write,Edit,Glob,Grep' \
    --allowedTools 'Bash,Read,Write,Edit,Glob,Grep,mcp__lean-lsp__*' \
    --disallowedTools 'WebSearch,WebFetch' \
    --setting-sources '' --strict-mcp-config "$@"
}
