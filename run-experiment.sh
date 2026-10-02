#!/bin/bash
# Fresh trial each invocation: copy experiment/ → runs/<id>/, run agent there,
# and on success extract the proof to results/<id>/. Next run never sees prior proofs.
set -euo pipefail

cd "$(dirname "$0")"

PLATFORM="${PLATFORM:-linux/amd64}"
IMAGE="${IMAGE:-midnight-agent}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
TEMPLATE="$PWD/experiment"
RUN_DIR="$PWD/runs/$RUN_ID"
RESULT_DIR="$PWD/results/$RUN_ID"
CACHE_DIR="$PWD/cache"

mkdir -p "$PWD/runs" "$PWD/results" "$CACHE_DIR"

# Seed package cache from a leftover template .lake once, then drop it from experiment/.
if [[ ! -d "$CACHE_DIR/packages" && -d "$TEMPLATE/.lake/packages" ]]; then
  echo "Seeding cache/ from experiment/.lake/packages"
  cp -a "$TEMPLATE/.lake/packages" "$CACHE_DIR/packages"
fi
if [[ -d "$TEMPLATE/.lake" ]]; then
  echo "Removing experiment/.lake (template must stay clean)"
  rm -rf "$TEMPLATE/.lake"
fi
rm -rf "$TEMPLATE/out"

echo "Preparing run $RUN_ID"
mkdir -p "$RUN_DIR"
# No .lake / out from the template — each trial starts from the stub proof only.
cp -a "$TEMPLATE/." "$RUN_DIR/"
rm -rf "$RUN_DIR/.lake" "$RUN_DIR/out"

docker build --platform "$PLATFORM" -t "$IMAGE" .

echo "Warming Lean deps + solc in $RUN_DIR"
docker run --rm \
  --platform "$PLATFORM" \
  -v "$RUN_DIR:/work" \
  -v "$CACHE_DIR:/cache" \
  -w /work \
  "$IMAGE" \
  bash -lc '
    set -euo pipefail
    mkdir -p .lake
    if [[ -d /cache/packages ]]; then
      rm -rf .lake/packages
      cp -a /cache/packages .lake/packages
    fi
    if [[ -f /cache/solidity-import/solc-0.8.34 ]]; then
      mkdir -p .lake/solidity-import
      cp -a /cache/solidity-import/solc-0.8.34 .lake/solidity-import/solc-0.8.34
    fi
    lake update
    python3 .lake/packages/verity/scripts/setup_solc_import.py \
      --output .lake/solidity-import/solc-0.8.34
    rm -rf /cache/packages
    cp -a .lake/packages /cache/packages
    mkdir -p /cache/solidity-import
    cp -a .lake/solidity-import/solc-0.8.34 /cache/solidity-import/solc-0.8.34
    lake build Midnight.Import
  '

echo "Starting agent on $RUN_DIR"
docker run --rm \
  --platform "$PLATFORM" \
  -e CURSOR_API_KEY \
  -v "$RUN_DIR:/work" \
  -w /work \
  "$IMAGE" \
  agent -p --force --trust --sandbox disabled \
  --model gpt-5.6-sol-high \
  --workspace /work \
  "Prove updatePositionViewProperties. Follow README.md. Stop when ./check/check_proof.sh exits 0."

echo "Checking proof"
if docker run --rm \
  --platform "$PLATFORM" \
  -v "$RUN_DIR:/work" \
  -w /work \
  "$IMAGE" \
  bash -lc './check/check_proof.sh'
then
  mkdir -p "$RESULT_DIR"
  cp -a "$RUN_DIR/Midnight" "$RESULT_DIR/"
  cp -a "$RUN_DIR/out" "$RESULT_DIR/" 2>/dev/null || true
  printf '%s\n' "$RUN_ID" > "$RESULT_DIR/RUN_ID"
  echo "SUCCESS — proof saved to $RESULT_DIR"
  echo "Run directory kept at $RUN_DIR"
  exit 0
else
  echo "FAILED — proof not extracted. Inspect $RUN_DIR"
  exit 1
fi
