#!/usr/bin/env python3
"""Reject sorry, admit, and any axiom outside Lean's standard three."""

import re
import sys
from pathlib import Path

text = Path("out/axioms.txt").read_text()
expected = {
    "Midnight.updatePositionViewProperties",
    "midnight.covered",
}
allowed = {"propext", "Classical.choice", "Quot.sound"}
seen = set()
failed = False
for name, axioms in re.findall(r"'([^']+)' depends on axioms: \[([^]]*)\]", text):
    have = {a.strip() for a in axioms.split(",") if a.strip()}
    extra = have - allowed
    seen.add(name)
    if extra:
        print(f"{name} uses disallowed axioms: {sorted(extra)}", file=sys.stderr)
        failed = True
if seen != expected:
    print(f"missing or unexpected axiom report: seen={sorted(seen)}", file=sys.stderr)
    failed = True
if failed:
    sys.exit(1)
print(text, end="")
