#!/usr/bin/env python3
"""Select the wExp proof task in a fresh run, preserving the original template."""

import hashlib
from pathlib import Path
import re
import sys


def prepare(root: Path) -> None:
    overrides = {
        "Midnight/Proof.lean": """import Midnight.TickLibSpec
namespace Midnight
theorem wExpIsMonotonic : Spec.wExpIsMonotonic := by
  sorry
end Midnight
""",
        "Midnight.lean": """import Midnight.TickLibSpec
import Midnight.Proof
""",
        "check/Goal.lean": """import Midnight

-- Reject a proof of a different statement.
example : Midnight.Spec.wExpIsMonotonic := Midnight.wExpIsMonotonic

#print axioms Midnight.wExpIsMonotonic
""",
        "README.md": """# Prove `wExpIsMonotonic`

`Midnight/TickLibSpec.lean` defines a manual word-level model of Solidity's
`TickLib.wExp` and the statement `Midnight.Spec.wExpIsMonotonic`:

```lean
∀ (x y : Int256),
  inWExpRange x → inWExpRange y →
  x > y → TickLib.wExp x ≥ TickLib.wExp y
```

Produce a proof that `./check/check_proof.sh` accepts.

## What you may edit

- `Midnight/Proof.lean`
- New files under `Midnight/`, including `Midnight/Lemmas/`

## What you may not edit

- Existing files under `Midnight/` other than `Midnight/Proof.lean`
- `Midnight.lean`, `lakefile.lean`, `lake-manifest.json`, `lean-toolchain`
- `README.md`, `AGENTS.md`, `vendor/`, `check/`

The model and specification in `Midnight/TickLibSpec.lean` are frozen.
Prove the exact statement; do not replace the model or weaken its input range.
No Solidity-equivalence proof is required by this task.

## What counts as done

`./check/check_proof.sh` exits 0. It checks the frozen files, builds the
library, verifies the theorem's type, and rejects axioms beyond `propext`,
`Classical.choice`, and `Quot.sound`. `sorry`, `admit`, extra axioms, and
`Lean.ofReduceBool` from `native_decide` are not accepted.

lean-lsp MCP is required. Follow `AGENTS.md`; if it is unavailable, write
`out/mcp-unavailable` and stop.

## Loop

```sh
lake build Midnight.Proof
./check/check_proof.sh
```

Work only in this directory. Do not read parent directories or other checkouts.
Do not look up a published proof on GitHub or in git history.
""",
    }
    for rel, contents in overrides.items():
        (root / rel).write_text(contents)

    axioms = root / "check/check_axioms.py"
    contents = axioms.read_text().replace(
        '"Midnight.updatePositionViewProperties",\n    "midnight.covered",',
        '"Midnight.wExpIsMonotonic",',
    )
    # Lean also prints this form for proofs with no axioms at all.
    contents = contents.replace(
        "seen = set()",
        "seen = set(re.findall(r\"'([^']+)' does not depend on any axioms\", text))",
    )
    axioms.write_text(contents)

    smoke = root / "scripts/check-lean-mcp.py"
    smoke.write_text(smoke.read_text().replace(
        '"file_path": "Midnight/Spec.lean"',
        '"file_path": "Midnight/TickLibSpec.lean"',
    ))

    checker = root / "check/check_frozen.py"
    contents = checker.read_text()
    for rel in [*overrides, "check/check_axioms.py"]:
        digest = hashlib.sha256((root / rel).read_bytes()).hexdigest()
        pattern = rf"('{re.escape(rel)}': ')[0-9a-f]{{64}}(')"
        contents, count = re.subn(pattern, rf"\g<1>{digest}\g<2>", contents)
        if count != 1:
            raise RuntimeError(f"Expected one frozen/initial digest for {rel}, got {count}")
    for rel in ["Midnight/TickLibSpec.lean", "AGENTS.md", "scripts/check-lean-mcp.py"]:
        digest = hashlib.sha256((root / rel).read_bytes()).hexdigest()
        pattern = rf"('{re.escape(rel)}': ')[0-9a-f]{{64}}(')"
        contents, count = re.subn(pattern, rf"\g<1>{digest}\g<2>", contents)
        if count == 0:
            contents = contents.replace("EXPECTED = {", f"EXPECTED = {{\n    '{rel}': '{digest}',", 1)
    checker.write_text(contents)


if __name__ == "__main__":
    prepare(Path(sys.argv[1]).resolve())
