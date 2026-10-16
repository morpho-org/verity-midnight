# Morpho Midnight prove experiment

Run a Cursor, Codex or Claude Code agent in Docker against a frozen Lean proof task:
prove `Midnight.Spec.updatePositionViewProperties` for Morpho Midnight’s
`updatePositionView` (via Verity’s Solidity import).

Each invocation is an isolated trial: the agent gets a fresh copy of the task
template and cannot see proofs from earlier runs. A successful proof is copied
to `results/`.

Proofs of this theorem are published on GitHub, and Verity's own docs point to
them. So agents also run without general internet access: an egress proxy lets
them reach only the model API, hosted web search is turned off where the
backend allows it, and their transcripts are audited after each run (see
[Answer isolation](#answer-isolation)).

## Prerequisites

- Docker. The image builds for the host's native platform: `linux/arm64` on
  Apple Silicon or ARM servers, `linux/amd64` on Intel/AMD (override with
  `PLATFORM`). solc is the exception: Verity's importer only accepts the
  official `linux-amd64` binary on Linux, so on `linux/arm64` it runs under
  amd64 emulation. Docker Desktop provides that with "Use Rosetta for
  x86_64/amd64 emulation"; on an ARM Linux server, run
  `docker run --privileged --rm tonistiigi/binfmt --install amd64` once.
  Warm-up checks that solc runs and says what to do if it does not.
- An API key for your chosen backend: `CURSOR_API_KEY` for Cursor (default),
  or `CODEX_API_KEY` for Codex (an OpenAI Platform API key). Codex can also
  use an existing ChatGPT sign-in with `CODEX_AUTH=chatgpt`.
  Claude uses `ANTHROPIC_API_KEY` or a subscription token (see below).
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

To use Claude Code with API credits:

```sh
export ANTHROPIC_API_KEY=…
AGENT_BACKEND=claude AGENT_MODEL=opus ./run-experiment.sh
```

To use your Claude subscription with browser sign-in and a cached login:

```sh
bash scripts/claude-login.sh
CLAUDE_AUTH=login AGENT_BACKEND=claude AGENT_MODEL=claude-opus-5-5 EXPERIMENT_TASK=wexp-positive MONITOR_INTERVAL=1m ./run-experiment.sh
```

Before starting the agents, the runner checks that the cached access token
outlives the run (prover timeout plus retrospective timeout plus 15 minutes). If
it does not, `scripts/claude-refresh.sh` refreshes it once, with one minimal
Haiku request, and writes the new login back to the cache. Both agents then
share a token that does not expire mid-run, so neither refreshes it: a refresh
rotates the refresh token and would log the other agent out.

Complete the browser sign-in using the URL printed by the login command. If
the browser callback cannot reach Docker, paste the returned code into that
terminal. The login cache stays in gitignored `.auth/claude/`; the runner
copies only credentials into separate prover and monitor homes. The login
runs inside Linux so credentials are stored in a portable file rather than
the macOS Keychain. Use `CLAUDE_AUTH_FILE` for a different Linux credential
cache, or `CLAUDE_AUTH_DIR` to choose the login helper's directory.

Alternatively, generate a token on the host and export the
token printed by the command:

```sh
claude setup-token
export CLAUDE_CODE_OAUTH_TOKEN=…
CLAUDE_AUTH=oauth AGENT_BACKEND=claude AGENT_MODEL=opus EXPERIMENT_TASK=wexp-positive MONITOR_INTERVAL=1m ./run-experiment.sh
```

The token uses your subscription's usage limits. A host `claude auth login`
alone does not provide credentials to Docker when its cache is in the macOS
Keychain. The token alternative is described in the
[Claude authentication documentation](https://code.claude.com/docs/en/authentication#generate-a-long-lived-token).
Both prover and monitor use the chosen model; set `MONITOR_MODEL=sonnet` to
choose a different monitor model. Model aliases follow Claude Code's current
defaults; use a full model ID for a reproducible choice.

To run the `wExp` monotonicity task using its manual Lean model:

```sh
EXPERIMENT_TASK=wexp AGENT_BACKEND=codex AGENT_MODEL=gpt-6.1-sol ./run-experiment.sh
```

This selects `Midnight.Spec.wExpIsMonotonic` in a fresh run and freezes
`Midnight/TickLibSpec.lean`. The original proof task remains the default.

To prove monotonicity and successful execution of the unsigned Solidity
implementation imported through Verity:

```sh
CODEX_AUTH=chatgpt AGENT_BACKEND=codex AGENT_MODEL=gpt-6.1-sol EXPERIMENT_TASK=wexp-positive MONITOR_INTERVAL=1m ./run-experiment.sh
```

This freezes `solidity/TickLibPositive.sol`, `Midnight/TickLibPositiveImport.lean`,
and `Midnight/TickLibPositiveSpec.lean`. Both properties must pass the checker.

To use your ChatGPT subscription instead of API credits, sign in on the host:

```sh
codex login
codex login status
CODEX_AUTH=chatgpt EXPERIMENT_TASK=wexp AGENT_BACKEND=codex AGENT_MODEL=gpt-6.1-sol MONITOR_INTERVAL=1m ./run-experiment.sh
```

The runner copies the login cache from `${CODEX_HOME:-$HOME/.codex}/auth.json`
into each agent's isolated home and forwards no API key in this mode.
Use `CODEX_AUTH_FILE` to select a different cache file. If the CLI uses the
OS keychain, use `codex -c cli_auth_credentials_store='"file"' login`
to create a file-based login cache. ChatGPT plan usage limits still apply.
This follows the [official Docker authentication workflow](https://learn.chatgpt.com/docs/auth#fallback-authenticate-locally-and-copy-your-auth-cache).

Switch back with `AGENT_BACKEND=cursor ./run-experiment.sh`. Both prover and
monitor use the selected backend. In API-key mode, export the key in your shell; the
scripts do not load `.env` automatically. Only the selected backend's key is
passed to agent containers; dependency setup, MCP preflight, and checker
containers receive no key. Keys are never baked into the image.

What the script does:

1. Copy clean `experiment/` → `runs/<timestamp>/`
2. Build the `midnight-agent` image (Lean 4.31, elan, Cursor `agent`, Codex, Claude Code, Python)
3. Inside Docker: `lake update`, install pinned linux `solc`,
   `lake build Midnight.Import` (`lean-lsp-mcp` is already in the image)
4. Start the egress proxy and check that GitHub is unreachable from the agent
   network (skipped with `EGRESS=0`)
5. Run the selected agent on that run directory (default timeout **120m**), with
   Lean MCP configured through `.cursor/mcp.json` for Cursor or an isolated
   Codex home with `config.toml` and `required = true` for Codex, or an explicit
   `--mcp-config` for Claude
6. Audit the prover transcripts (`scripts/audit_transcripts.py`)
7. Run `./check/check_proof.sh` in Docker with no network
8. On success, copy `Midnight/` (and `out/` if present) and the audit report to
   `results/<timestamp>/`

## Proof aids for imported models

Agents get help with the memory-heavy parts of reasoning about
`solidity_import` models:

- `experiment/SOLIDITY_IMPORT.md`: how to run an imported body symbolically
  without exhausting memory. `AGENTS.md` and the task READMEs point to it.
- `experiment/ProofKit/`: generic step lemmas, signed-word (`int256` ↔ `Int`) lemmas and a `run_exec` tactic for the
  `Denote` interpreter (`import ProofKit`), prebuilt during warm-up. It
  contains nothing specific to a task.
- Every Lean process in the image runs with `-M $LEAN_MEMORY_MB`, so a runaway
  proof fails with `excessive memory consumption detected` instead of an OOM
  kill. The toolchain's `lean` is a wrapper (`scripts/lean-memory-cap.sh`), and
  the language server passes the cap on to its workers.
- `leanrun` (`scripts/leanrun`, on `PATH`) runs one Lean command and reports
  exit status, peak memory and wall time.
- `experiment/scripts/lean-mcp.sh` limits lean-lsp-mcp to two open files and
  elaborates `Midnight/Proof.lean` at startup, so the symbol index is ready
  before the first search.

These files are frozen like the task files. Runs before they were added had
none of them, so compare results across that change with care.

## Verity version

The template pins Verity `10f697bb` (2026-10-12), the version that also imports
`int256` and `TickLib.wExp`'s recursive call. Moving from `9b472a8` changed the
`updatePositionView` task:

- The importer no longer generates a typed wrapper for
  `updatePositionView(Market, bytes32, address)`. The body now decodes its
  arguments from ABI call data (69 statements instead of 28).
- `Midnight/Spec.lean` therefore states the rule with `runFunction` over any
  call data, reading `id` and `user` from it. `Requires`, `Asserts` and the
  storage reads are unchanged. `check/UpdatePositionViewSmoke.lean`, run during
  warm-up, shows the call succeeds on real ABI input and rejects a bad address.

Results from before the change were proved against the old model and spec, so
compare them with care.

`lean-lsp-mcp` is installed at `/opt/lean-mcp` in the Dockerfile (pins from
`experiment/scripts/lean-mcp-requirements.txt`). Helpers match
[morpho-midnight-verity `cursor/proof-sandbox`](https://github.com/lfglabs-dev/morpho-midnight-verity/tree/cursor/proof-sandbox).

## Useful knobs

| Variable | Default | Meaning |
|----------|---------|---------|
| `AGENT_BACKEND` | `cursor` | `cursor`, `codex` or `claude`; applies to prover and monitor |
| `CURSOR_API_KEY` | (required for Cursor) | Cursor agent authentication |
| `CODEX_API_KEY` | (required for Codex API-key mode) | OpenAI Platform API key; read directly by `codex exec` |
| `CODEX_AUTH` | `api-key` | Codex authentication: `api-key` or `chatgpt` |
| `CODEX_AUTH_FILE` | `${CODEX_HOME:-$HOME/.codex}/auth.json` | Host ChatGPT login cache copied into isolated agent homes |
| `ANTHROPIC_API_KEY` | (required for Claude API-key mode) | Anthropic API key |
| `CLAUDE_AUTH` | `api-key` | Claude authentication: `api-key`, `oauth` or `login` |
| `CLAUDE_AUTH_FILE` | `.auth/claude/.credentials.json` | Browser login cache copied into isolated agent homes |
| `CLAUDE_CODE_OAUTH_TOKEN` | (required for Claude OAuth mode) | Subscription token from `claude setup-token` |
| `AGENT_MODEL` | Cursor: `gpt-5.6-sol-high`; Codex: `gpt-6.1-sol`; Claude: `opus` | Model ID or alias for the selected backend |
| `AGENT_REASONING_EFFORT` | `high` | Codex or Claude reasoning effort, separate from model ID; ignored by Cursor |
| `MONITOR_REASONING_EFFORT` | `$AGENT_REASONING_EFFORT` | Codex or Claude monitor reasoning effort |
| `AGENT_TIMEOUT` | `120m` | Cap on the prover agent step only (`timeout(1)` inside the container) |
| `LEAN_MEMORY_MB` | `6144` | Per-process Lean memory cap (`lean -M`) in the prover container; `0` disables it. Warm-up and the final checker run uncapped |
| `MONITOR` | `1` | Set `0` to disable the sidecar progress agent |
| `MONITOR_MODEL` | `$AGENT_MODEL` | Model for the monitor / retrospective agent |
| `MONITOR_INTERVAL` | `2m` | How often the monitor journals (`30s` / `2m` / `1h`) |
| `MONITOR_RETRO_TIMEOUT` | `20m` | Max wait after the prover stops for the retrospective |
| `EGRESS` | `1` | Set `0` to give agents unrestricted network access (the audit then fails any network command) |
| `EGRESS_ALLOW_EXTRA` | (empty) | Extra hosts the agents may reach, as space-separated extended regexes on the host name |
| `PLATFORM` | host's native (`linux/arm64` or `linux/amd64`) | Docker platform of the agent image (`scripts/platform.sh`) |
| `IMAGE` | `midnight-agent` | Image name |

Codex CLI is pinned to `0.162.0` in the Dockerfile. To change it, update the
`CODEX_VERSION` build argument default. Codex uses noninteractive `codex exec`
with approval prompts and its inner sandbox disabled; Docker provides the
isolation, including read-only prover mounts in the monitor container.
See [Codex automation](https://learn.chatgpt.com/docs/non-interactive-mode) and
[MCP configuration](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).

Claude Code is pinned to `2.1.300` (`CLAUDE_VERSION` in the Dockerfile).
It runs with explicit Bash/file/Lean MCP tool approvals and `dontAsk` permission
mode inside Docker. Hosted web tools, cloud connectors, automatic updates and
nonessential traffic are disabled. The monitor has no MCP servers and resumes
its own conversation with `--continue`. See
[Claude automation](https://code.claude.com/docs/en/headless).

While the prover runs, `[prover]` and `[monitor]` lines are streamed to the host
stdout. The monitor keeps one resumed session with a separate RW volume
(`monitor-logs/<id>/`); the prover workspace is mounted **read-only** at
`/prover`. Journal and retrospective live only under `monitor-logs/<id>/`
(not visible to the prover).
Run IDs include the backend name. Cursor transcripts remain in its isolated
home; Codex and Claude events are saved to
`runs/<id>/.prover-<backend>/prover-events.jsonl`.
The monitor reads these through a separate read-only mount. Codex and Claude resume their
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
| `2` | Also: egress preflight found GitHub reachable from the agent network |
| `91` | Agent wrote `out/mcp-unavailable` (MCP required; see `AGENTS.md`) |
| `92` | Transcript audit flagged a possible answer lookup; proof not checked |
| `124` | Agent hit `AGENT_TIMEOUT` |

Non-zero failures keep the run directory for inspection. Proofs are only written
under `results/` when the checker passes.

## Layout

| Path | Role |
|------|------|
| `experiment/` | Immutable task template (stub `Proof.lean`, frozen Import/Spec/check/vendor); `check_frozen.py --start` pins the stub before each trial |
| `runs/<id>/` | Prover trial workspace (gitignored) |
| `monitor-logs/<id>/` | Monitor journal / retrospective (RW for monitor only; gitignored) |
| `audit-logs/<id>/` | Egress allowlist, proxy log and transcript audit report (gitignored) |
| `results/<id>/` | Extracted proof after a passing check (gitignored) |
| `cache/` | Warm Lake packages + linux `solc` between runs (gitignored) |
| `Dockerfile` | Toolchain image |
| `run-experiment.sh` | Orchestrates a trial |

Task rules for the agent (what may be edited, acceptance criteria) are in
[`experiment/README.md`](experiment/README.md). MCP usage notes are in
[`experiment/AGENTS.md`](experiment/AGENTS.md).

## Answer isolation

Three layers keep the prover from finding a published proof instead of
writing one:

1. **Egress allowlist.** Prover and monitor containers run on an internal
   Docker network. Their only route out is a tinyproxy container that forwards
   to the hosts in `EGRESS_ALLOW_DEFAULT` (`scripts/agent-backend.sh`) plus
   `EGRESS_ALLOW_EXTRA`, so `git`, `curl` and Lake cannot reach GitHub. The
   run refuses to start the agent if `github.com` answers from that network.
   The Cursor defaults are a best guess at its API hosts: if the Cursor agent
   cannot connect, look for refused hosts in `audit-logs/<id>/tinyproxy.log`
   and add them with `EGRESS_ALLOW_EXTRA`.
2. **No hosted web tools.** Web search runs on the model provider's side, so
   the proxy cannot stop it. Codex runs with `web_search = "disabled"`.
   Claude exposes only Bash/file/Lean MCP tools and explicitly denies
   `WebSearch` and `WebFetch`.
   Cursor's `experiment/.cursor/cli.json` denies `WebFetch`; the Cursor CLI has
   no documented switch for web search, so layer 3 covers it.
3. **Transcript audit.** After the prover stops, `scripts/audit_transcripts.py`
   writes `audit-logs/<id>/audit.md`. Any web search or web fetch tool call
   fails the run with exit code `92`, as does any network command when
   `EGRESS=0`. Hosts refused by the proxy and mentions of the published proof
   repository are listed for review only: the agent CLIs contact GitHub on
   their own, and Verity's docs name the repository.

The checker container runs with `--network none`. Lake dependencies and `solc`
are fetched in the warm-up container before the agent starts, which keeps its
normal network access. `./shell.sh` is not isolated.

## Interactive shell

```sh
./shell.sh                 # mount experiment/ (keep the template clean)
./shell.sh <run-id>        # mount runs/<run-id>/ + cache/
./shell.sh runs/<run-id>   # same, explicit path
AGENT_BACKEND=codex ./shell.sh <run-id>
CLAUDE_AUTH=oauth AGENT_BACKEND=claude ./shell.sh <run-id>
```

Uses `AGENT_BACKEND` / `PLATFORM` / `IMAGE` like `run-experiment.sh`. For Codex,
the shell mounts the Lean MCP configuration and forwards `CODEX_API_KEY`.
Noninteractive `codex exec` uses that key directly. For the interactive Codex
CLI, first run `printenv CODEX_API_KEY | codex login --with-api-key` inside the
container. Prefer a `runs/<id>` mount
for Lean builds so `experiment/` stays the clean template.

For Claude, the shell forwards the selected API key or OAuth token. Inside it,
run `claude --strict-mcp-config --mcp-config /opt/midnight/claude-prover.json`
to connect the Lean MCP server. Use `AGENT_MODEL` to choose the experiment's
model; the interactive CLI also accepts `--model`.

Credential-free runner checks: `python3 scripts/test_claude_backend.py`.
