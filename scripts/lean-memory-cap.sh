#!/bin/sh
# Installed as the toolchain's `lean`; the real binary is `lean-real` beside it.
# Passes Lean's own memory cap so a runaway elaboration fails with
# "excessive memory consumption detected" instead of an OOM kill. `lake build`,
# `lake env lean` and the language server all start Lean through this path,
# and the server passes the cap on to its file workers.
# LEAN_MEMORY_MB=0 disables the cap.
mb="${LEAN_MEMORY_MB:-6144}"
real="$(dirname "$0")/lean-real"
if [ "$mb" = 0 ]; then
  exec "$real" "$@"
fi
exec "$real" -M "$mb" "$@"
