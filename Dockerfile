FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git python3 python3-venv ripgrep tinyproxy zstd \
    && rm -rf /var/lib/apt/lists/*

# Lean / Lake
# pipefail: a failed curl must fail the layer (otherwise elan never installs
# but the RUN still exits 0).
RUN set -eux; \
    curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf \
      | sh -s -- -y --default-toolchain none
ENV PATH="/root/.elan/bin:${PATH}"
# Pin matches experiment/lean-toolchain
RUN elan toolchain install leanprover/lean4:v4.31.0 \
    && elan default leanprover/lean4:v4.31.0

# lean-lsp-mcp (stdio diagnostics for the agent); pins from experiment/scripts/
COPY experiment/scripts/lean-mcp-requirements.txt /tmp/lean-mcp-requirements.txt
RUN set -eux; \
    python3 -m venv /opt/lean-mcp; \
    /opt/lean-mcp/bin/python -m pip install --disable-pip-version-check \
      -r /tmp/lean-mcp-requirements.txt; \
    /opt/lean-mcp/bin/lean-lsp-mcp --version; \
    rm /tmp/lean-mcp-requirements.txt
ENV PATH="/opt/lean-mcp/bin:${PATH}"

# Cursor agent CLI
RUN curl https://cursor.com/install -fsS | bash
ENV PATH="/root/.local/bin:${PATH}"

# Agent CLIs (all backends are available in the same image).
ARG CODEX_VERSION=0.162.0
RUN apt-get update && apt-get install -y --no-install-recommends nodejs npm \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g "@openai/codex@${CODEX_VERSION}" \
    && codex --version

ARG CLAUDE_VERSION=2.1.300
RUN curl -fsSL https://claude.ai/install.sh -o /tmp/install-claude.sh \
    && bash /tmp/install-claude.sh "${CLAUDE_VERSION}" \
    && rm /tmp/install-claude.sh \
    && claude --version

COPY scripts/run-prover.sh scripts/monitor-prover-loop.sh scripts/claude-common.sh scripts/claude-prover.json scripts/egress/tinyproxy.conf scripts/install-solc.py /opt/midnight/

# Cap each Lean process's memory (LEAN_MEMORY_MB, default 6144) so runaway
# proofs fail with a Lean error instead of an OOM kill; `leanrun` reports
# exit status, peak memory and time for one Lean command.
COPY scripts/lean-memory-cap.sh scripts/leanrun /tmp/lean-tools/
RUN set -eux; \
    bin="/root/.elan/toolchains/leanprover--lean4---v4.31.0/bin"; \
    mv "$bin/lean" "$bin/lean-real"; \
    install -m 755 /tmp/lean-tools/lean-memory-cap.sh "$bin/lean"; \
    install -m 755 /tmp/lean-tools/leanrun /usr/local/bin/leanrun; \
    rm -r /tmp/lean-tools; \
    lean --version

WORKDIR /work
