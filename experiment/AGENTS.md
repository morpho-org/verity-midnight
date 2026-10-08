# Agent notes

Follow `README.md` for the proof task and edit rules.

## Lean diagnostics MCP

`scripts/lean-mcp.sh` launches pinned `lean-lsp-mcp` from `/opt/lean-mcp` (image)
or `.lake/lean-mcp` (fallback). Cursor loads it from `.cursor/mcp.json`. Use
`lean_diagnostic_messages`, `lean_goal`, `lean_hover_info`, and `lean_local_search`
for compiler feedback. These do not replace `./check/check_proof.sh`.

Optional smoke test:

```sh
/opt/lean-mcp/bin/python scripts/check-lean-mcp.py
```
