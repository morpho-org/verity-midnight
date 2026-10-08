# Agent notes

Follow `README.md` for the proof task and edit rules.

## Lean diagnostics MCP (required)

lean-lsp MCP is **required** for this task. Use `lean_diagnostic_messages`,
`lean_goal`, `lean_hover_info`, and `lean_local_search` for compiler feedback.
These do not replace `./check/check_proof.sh`.

`scripts/lean-mcp.sh` launches pinned `lean-lsp-mcp` from `/opt/lean-mcp` (image)
or `.lake/lean-mcp` (fallback). Cursor loads it from `.cursor/mcp.json`.

### If MCP is unavailable — stop immediately

Do **not** continue the proof with shell-only Lean. Terminate the session:

1. Write a one-line reason to `out/mcp-unavailable` (create `out/` if needed).
2. Stop; do not edit `Midnight/Proof.lean` further.

The host treats `out/mcp-unavailable` as failure (exit code **91**).

Optional smoke test:

```sh
/opt/lean-mcp/bin/python scripts/check-lean-mcp.py
```

Preflight (also run by `run-experiment.sh` before the agent):

```sh
sh scripts/require-lean-mcp.sh
```

### Interactive debug

MCP config is `.cursor/mcp.json` (absolute `/work/scripts/lean-mcp.sh` — the CLI
does not expand `${workspaceFolder}`). In a fresh container:

```sh
sh scripts/require-lean-mcp.sh
agent --force --approve-mcps --workspace /work
```

`--approve-mcps` auto-approves servers for that agent session; `mcp enable`
persists approval in the container home (lost when the container exits).
