# Morpho Midnight prove experiment

Run a Cursor or Codex agent in Docker against a frozen Lean proof task:
prove `Midnight.Spec.updatePositionViewProperties` for Morpho Midnight’s
`updatePositionView` (via Verity’s Solidity import).

Each invocation is an isolated trial: the agent gets a fresh copy of the task
template and cannot see proofs from earlier runs. A successful proof is copied
to `results/`.

## Prerequisites

- Docker (on Apple Silicon, the image builds as `linux/amd64`)
- An API key for your chosen backend: `CURSOR_API_KEY` for Cursor (default),
  or `CODEX_API_KEY` for Codex (an OpenAI Platform API key)
- Git submodules initialized (Midnight Solidity sources):

```sh
git submodule update --init --recursive
```

## Run

```sh
export CURSOR_API_KEY=…   # if not already set
./run-experiment.sh
```

To use Codex:

```sh
export CODEX_API_KEY=…
AGENT_BACKEND=codex ./run-experiment.sh
```

Switch back with `AGENT_BACKEND=cursor ./run-experiment.sh`. Both prover and
monitor use the selected backend. Keys must be exported in your shell; the
scripts do not load `.env` automatically. Only the selected backend's key is
passed to agent containers; dependency setup, MCP preflight, and checker
containers receive no key. Keys are never baked into the image.

What the script does:

1. Copy clean `experiment/` → `runs/<timestamp>/`
2. Build the `midnight-agent` image (Lean 4.31, elan, Cursor `agent`, Codex, Python)
3. Inside Docker: `lake update`, install pinned linux `solc`,
   `lake build Midnight.Import` (`lean-lsp-mcp` is already in the image)
4. Run the selected agent on that run directory (default timeout **120m**), with
   Lean MCP configured through `.cursor/mcp.json` for Cursor or an isolated
   Codex home with `config.toml` and `required = true` for Codex
5. Run `./check/check_proof.sh` in Docker
6. On success, copy `Midnight/` (and `out/` if present) to `results/<timestamp>/`

`lean-lsp-mcp` is installed at `/opt/lean-mcp` in the Dockerfile (pins from
`experiment/scripts/lean-mcp-requirements.txt`). Helpers match
[morpho-midnight-verity `cursor/proof-sandbox`](https://github.com/lfglabs-dev/morpho-midnight-verity/tree/cursor/proof-sandbox).

## Useful knobs

| Variable | Default | Meaning |
|----------|---------|---------|
| `AGENT_BACKEND` | `cursor` | `cursor` or `codex`; applies to prover and monitor |
| `CURSOR_API_KEY` | (required for Cursor) | Cursor agent authentication |
| `CODEX_API_KEY` | (required for Codex) | OpenAI Platform API key; read directly by `codex exec` |
| `AGENT_MODEL` | Cursor: `gpt-5.6-sol-high`; Codex: `gpt-5.6-sol` | Model ID for the selected backend; Cursor aliases are not OpenAI API model IDs |
| `AGENT_REASONING_EFFORT` | `high` | Codex reasoning effort, separate from model ID; ignored by Cursor |
| `MONITOR_REASONING_EFFORT` | `$AGENT_REASONING_EFFORT` | Codex monitor reasoning effort |
| `AGENT_TIMEOUT` | `120m` | Cap on the prover agent step only (`timeout(1)` inside the container) |
| `MONITOR` | `1` | Set `0` to disable the sidecar progress agent |
| `MONITOR_MODEL` | `$AGENT_MODEL` | Model for the monitor / retrospective agent |
| `MONITOR_INTERVAL` | `2m` | How often the monitor journals (`30s` / `2m` / `1h`) |
| `MONITOR_RETRO_TIMEOUT` | `20m` | Max wait after the prover stops for the retrospective |
| `PLATFORM` | `linux/amd64` | Docker platform |
| `IMAGE` | `midnight-agent` | Image name |

Codex CLI is pinned to `0.162.0` in the Dockerfile. To change it, update the
`CODEX_VERSION` build argument default. Codex uses noninteractive `codex exec`
with approval prompts and its inner sandbox disabled; Docker provides the
isolation, including read-only prover mounts in the monitor container.
See [Codex automation](https://learn.chatgpt.com/docs/non-interactive-mode) and
[MCP configuration](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).

While the prover runs, `[prover]` and `[monitor]` lines are streamed to the host
stdout. The monitor keeps one resumed session with a separate RW volume
(`monitor-logs/<id>/`); the prover workspace is mounted **read-only** at
`/prover`. Journal and retrospective live only under `monitor-logs/<id>/`
(not visible to the prover).
Run IDs include the backend name. Cursor transcripts remain in its isolated
home; Codex events are saved to `runs/<id>/.prover-codex/prover-events.jsonl`.
The monitor reads these through a separate read-only mount. Codex resumes its
own latest session between ticks; the prover always starts a fresh session.
Examples:

```sh
AGENT_TIMEOUT=30m ./run-experiment.sh
AGENT_MODEL=grok-4.7-high AGENT_TIMEOUT=90m ./run-experiment.sh
MONITOR_MODEL=composer-2.5-fast MONITOR_INTERVAL=1m ./run-experiment.sh
MONITOR=0 ./run-experiment.sh
AGENT_BACKEND=codex MONITOR=0 AGENT_TIMEOUT=30m ./run-experiment.sh
AGENT_BACKEND=codex AGENT_REASONING_EFFORT=xhigh ./run-experiment.sh
PLATFORM=linux/amd64 AGENT_TIMEOUT=2h ./run-experiment.sh
```

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Proof accepted; copied to `results/<id>/` |
| `1` | Agent finished but `./check/check_proof.sh` failed |
| `2` | Invalid backend/settings, missing API key, or lean-lsp MCP preflight failure (agent not started) |
| `91` | Agent wrote `out/mcp-unavailable` (MCP required; see `AGENTS.md`) |
| `124` | Agent hit `AGENT_TIMEOUT` |

Non-zero failures keep the run directory for inspection. Proofs are only written
under `results/` when the checker passes.

## Layout

| Path | Role |
|------|------|
| `experiment/` | Immutable task template (stub `Proof.lean`, frozen Import/Spec/check/vendor); `check_frozen.py --start` pins the stub before each trial |
| `runs/<id>/` | Prover trial workspace (gitignored) |
| `monitor-logs/<id>/` | Monitor journal / retrospective (RW for monitor only; gitignored) |
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
AGENT_BACKEND=codex ./shell.sh <run-id>
```

Uses `AGENT_BACKEND` / `PLATFORM` / `IMAGE` like `run-experiment.sh`. For Codex,
the shell mounts the Lean MCP configuration and forwards `CODEX_API_KEY`.
Noninteractive `codex exec` uses that key directly. For the interactive Codex
CLI, first run `printenv CODEX_API_KEY | codex login --with-api-key` inside the
container. Prefer a `runs/<id>` mount
for Lean builds so `experiment/` stays the clean template.
