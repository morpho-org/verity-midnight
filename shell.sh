#!/bin/bash
# Interactive shell in the experiment Docker image.
# Usage:
#   ./shell.sh              # mount experiment/ (read/debug only; keep it clean)
#   ./shell.sh <run-id>     # mount runs/<run-id>/ + cache/
#   ./shell.sh runs/<id>    # same, explicit path
set -euo pipefail

cd "$(dirname "$0")"

PLATFORM="${PLATFORM:-linux/amd64}"
IMAGE="${IMAGE:-midnight-agent}"

TARGET="${1:-experiment}"

if [[ "$TARGET" == runs/* ]]; then
  WORK_DIR="$PWD/$TARGET"
elif [[ "$TARGET" != "experiment" && -d "$PWD/runs/$TARGET" ]]; then
  WORK_DIR="$PWD/runs/$TARGET"
elif [[ "$TARGET" == "experiment" ]]; then
  WORK_DIR="$PWD/experiment"
else
  echo "Unknown target: $TARGET" >&2
  echo "Usage: $0 [experiment|runs/<id>|<run-id>]" >&2
  exit 1
fi

if [[ ! -d "$WORK_DIR" ]]; then
  echo "Directory not found: $WORK_DIR" >&2
  exit 1
fi

# Note: avoid empty "${array[@]}" under `set -u` — breaks on macOS /bin/bash 3.2.
if [[ "$WORK_DIR" == "$PWD/runs/"* ]]; then
  mkdir -p "$PWD/cache"
  echo "Mounting $WORK_DIR at /work (cache at /cache)."
  exec docker run --rm -it \
    --platform "$PLATFORM" \
    -e CURSOR_API_KEY \
    -v "$WORK_DIR:/work" \
    -v "$PWD/cache:/cache" \
    -w /work \
    "$IMAGE" \
    bash
fi

echo "Mounting experiment/ at /work — avoid leaving .lake or edits in the template."
exec docker run --rm -it \
  --platform "$PLATFORM" \
  -e CURSOR_API_KEY \
  -v "$WORK_DIR:/work" \
  -w /work \
  "$IMAGE" \
  bash
