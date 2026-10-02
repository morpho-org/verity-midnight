#!/bin/sh
# Exit 0 only when the frozen task is intact and the proof is accepted.
set -eu
cd "$(dirname "$0")/.."
python3 check/check_frozen.py
lake build
mkdir -p out
lake env lean check/Goal.lean > out/axioms.txt
python3 check/check_axioms.py
