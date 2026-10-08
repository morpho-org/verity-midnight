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
3. Inside Docker: `lake update`, install pinned linux `solc`, `lake build Midnight.Import`
4. Run the Cursor agent on that run directory (default timeout **1h**)
5. Run `./check/check_proof.sh` in Docker
6. On success, copy `Midnight/` (and `out/` if present) to `results/<timestamp>/`

## Useful knobs

| Variable | Default | Meaning |
|----------|---------|---------|
| `CURSOR_API_KEY` | (required) | Auth for the agent CLI |
| `AGENT_TIMEOUT` | `1h` | Cap on the agent step only (`timeout(1)` inside the container) |
| `PLATFORM` | `linux/amd64` | Docker platform |
| `IMAGE` | `midnight-agent` | Image name |

Examples:

```sh
AGENT_TIMEOUT=30m ./run-experiment.sh
PLATFORM=linux/amd64 AGENT_TIMEOUT=2h ./run-experiment.sh
```

Exit status **124** means the agent hit the timeout. Non-zero agent failures keep
the run directory for inspection; proofs are only written under `results/` when
the checker passes.

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
[`experiment/README.md`](experiment/README.md).

## Interactive shell

To debug the image with the same mounts the prep step uses:

```sh
docker run --rm -it --platform linux/amd64 \
  -v "$PWD/runs/<id>:/work" \
  -v "$PWD/cache:/cache" \
  -w /work \
  midnight-agent \
  bash
```

Or against a fresh copy of the template if you have not started a run yet:

```sh
docker run --rm -it --platform linux/amd64 \
  -v "$PWD/experiment:/work" \
  -w /work \
  midnight-agent \
  bash
```

Do not leave build artifacts in `experiment/`; keep that tree as the clean
template. Use `runs/` or throwaway mounts for Lean builds.
