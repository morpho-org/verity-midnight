FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git python3 python3-venv \
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

WORKDIR /work
