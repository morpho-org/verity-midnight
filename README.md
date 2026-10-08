# Morpho Midnight prove experiment

Run a Cursor agent in Docker against a frozen Lean proof task:
prove `Midnight.Spec.updatePositionViewProperties` for Morpho Midnight’s
`updatePositionView` (via Verity’s Solidity import).

Each invocation is an isolated trial: the agent gets a fresh copy of the task
template and cannot see proofs from earlier runs. A successful proof is copied
to `results/`.

## Prerequisites

- Docker (on Apple Silicon, the image builds as `linux/amd64`)
- A Cursor API key: set `CURSOR_API_KEY` in the environment
- Git submodules initialized (Midnight Solidity sources):

```sh
git submodule update --init --recursive
```

## Run

```sh
export CURSOR_API_KEY=…   # if not already set
./run-experiment.sh
```

What the script does:

1. Copy clean `experiment/` → `runs/<timestamp>/`
2. Build the `midnight-agent` image (Lean 4.31, elan, Cursor `agent`, Python)
3. Inside Docker: `lake update`, install pinned linux `solc`,
   `lake build Midnight.Import` (`lean-lsp-mcp` is already in the image)
4. Run the Cursor agent on that run directory (default timeout **1h**), with
   `--approve-mcps` so `.cursor/mcp.json` → `scripts/lean-mcp.sh` is available
5. Run `./check/check_proof.sh` in Docker
6. On success, copy `Midnight/` (and `out/` if present) to `results/<timestamp>/`

`lean-lsp-mcp` is installed at `/opt/lean-mcp` in the Dockerfile (pins from
`experiment/scripts/lean-mcp-requirements.txt`). Helpers match
[morpho-midnight-verity `cursor/proof-sandbox`](https://github.com/lfglabs-dev/morpho-midnight-verity/tree/cursor/proof-sandbox).

## Useful knobs

| Variable | Default | Meaning |
|----------|---------|---------|
| `CURSOR_API_KEY` | (required) | Auth for the agent CLI |
| `AGENT_MODEL` | `gpt-5.6-sol-high` | Cursor agent `--model` id (`agent --list-models`) |
| `AGENT_TIMEOUT` | `1h` | Cap on the agent step only (`timeout(1)` inside the container) |
| `PLATFORM` | `linux/amd64` | Docker platform |
| `IMAGE` | `midnight-agent` | Image name |

Examples:

```sh
AGENT_TIMEOUT=30m ./run-experiment.sh
AGENT_MODEL=grok-4.7-high AGENT_TIMEOUT=90m ./run-experiment.sh
PLATFORM=linux/amd64 AGENT_TIMEOUT=2h ./run-experiment.sh
```

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Proof accepted; copied to `results/<id>/` |
| `1` | Agent finished but `./check/check_proof.sh` failed |
| `2` | lean-lsp MCP preflight failed (agent not started) |
| `91` | Agent wrote `out/mcp-unavailable` (MCP required; see `AGENTS.md`) |
| `124` | Agent hit `AGENT_TIMEOUT` |

Non-zero failures keep the run directory for inspection. Proofs are only written
under `results/` when the checker passes.

## Layout

| Path | Role |
|------|------|
| `experiment/` | Immutable task template (stub `Proof.lean`, frozen Import/Spec/check/vendor) |
| `runs/<id>/` | One trial’s workspace (gitignored) |
| `results/<id>/` | Extracted proof after a passing check (gitignored) |
| `cache/` | Warm Lake packages + linux `solc` between runs (gitignored) |
| `Dockerfile` | Toolchain image |
| `run-experiment.sh` | Orchestrates a trial |

Task rules for the agent (what may be edited, acceptance criteria) are in
[`experiment/README.md`](experiment/README.md). MCP usage notes are in
[`experiment/AGENTS.md`](experiment/AGENTS.md).

## Interactive shell

```sh
./shell.sh                 # mount experiment/ (keep the template clean)
./shell.sh <run-id>        # mount runs/<run-id>/ + cache/
./shell.sh runs/<run-id>   # same, explicit path
```

Uses `PLATFORM` / `IMAGE` like `run-experiment.sh`. Prefer a `runs/<id>` mount
for Lean builds so `experiment/` stays the clean template.
