#!/usr/bin/env python3
"""Select the imported unsigned exponential task in a fresh experiment run."""

import hashlib
from pathlib import Path
import re
import runpy
import sys


def prepare(root: Path) -> None:
    base = runpy.run_path(str(Path(__file__).with_name("prepare-wexp-task.py")))
    base["prepare"](root)
    overrides = {
        "Midnight/Proof.lean": """import Midnight.TickLibPositiveSpec

namespace Midnight.TickLibPositive

theorem wExpIsMonotonic : Spec.TickLibPositive.wExpIsMonotonic := by
  sorry

theorem wExpSucceeds : Spec.TickLibPositive.wExpSucceeds := by
  sorry

end Midnight.TickLibPositive
""",
        "Midnight.lean": """import Midnight.TickLibPositiveSpec
import Midnight.Proof
""",
        "check/Goal.lean": """import Midnight

-- Both claims must be proved about the exact imported model.
example : Midnight.Spec.TickLibPositive.wExpIsMonotonic :=
  Midnight.TickLibPositive.wExpIsMonotonic
example : Midnight.Spec.TickLibPositive.wExpSucceeds :=
  Midnight.TickLibPositive.wExpSucceeds

#print axioms Midnight.TickLibPositive.wExpIsMonotonic
#print axioms Midnight.TickLibPositive.wExpSucceeds
#print axioms tickLibPositive.covered
""",
        "README.md": """# Prove the imported unsigned `wExp` properties

Prove both frozen statements in `Midnight/TickLibPositiveSpec.lean`:

1. `Midnight.Spec.TickLibPositive.wExpIsMonotonic`: for `x > y` in the
   nonnegative tick range, successful outputs satisfy `wExp(x) >= wExp(y)`.
2. `Midnight.Spec.TickLibPositive.wExpSucceeds`: every input in that range
   succeeds, ruling out vacuous monotonicity caused by reverts.

`Midnight/TickLibPositiveImport.lean` uses `solidity_import` to generate
`tickLibPositive.model` and `tickLibPositive.wExp` from
`solidity/TickLibPositive.sol`. Reason about that generated model. The Solidity
uses checked unsigned arithmetic, a sign/magnitude residual, and a bounded
power-of-two helper. The intended range is 0 through 16817989975223754156.
No equivalence proof to the original signed Solidity library is required.

Read `SOLIDITY_IMPORT.md` before your first proof attempt: it explains how to
run the imported body symbolically without exhausting memory, and the prebuilt
`ProofKit` lemmas (`import ProofKit`) that do it.

Produce proofs that `./check/check_proof.sh` accepts.

## What you may edit

- `Midnight/Proof.lean`
- New files under `Midnight/`, including `Midnight/Lemmas/`

## What you may not edit

- Existing files under `Midnight/` other than `Midnight/Proof.lean`
- `Midnight.lean`, `lakefile.lean`, `lake-manifest.json`, `lean-toolchain`
- `README.md`, `AGENTS.md`, `SOLIDITY_IMPORT.md`, `ProofKit/`, `vendor/`,
  `solidity/`, `check/`

The Solidity implementation, import and specification are frozen. Do not
replace the imported model or weaken either statement or its input range.

## What counts as done

`./check/check_proof.sh` exits 0. It checks the frozen files, builds the
library, checks both theorem types, and audits both proofs and
`tickLibPositive.covered`. Only `propext`, `Classical.choice`, and `Quot.sound`
are allowed. `sorry`, `admit`, extra axioms, and `native_decide` are rejected.

lean-lsp MCP is required. Follow `AGENTS.md`; if it is unavailable, write
`out/mcp-unavailable` and stop.

## Loop

```sh
lake build Midnight.Proof
./check/check_proof.sh
```

Work only in this directory. Do not read parent directories or other checkouts.
Do not look up published proofs on GitHub or in git history.
""",
    }
    for rel, contents in overrides.items():
        (root / rel).write_text(contents)

    axioms = root / "check/check_axioms.py"
    contents = axioms.read_text().replace(
        '"Midnight.wExpIsMonotonic",',
        '"Midnight.TickLibPositive.wExpIsMonotonic",\n'
        '    "Midnight.TickLibPositive.wExpSucceeds",\n'
        '    "tickLibPositive.covered",',
    )
    axioms.write_text(contents)
    smoke = root / "scripts/check-lean-mcp.py"
    smoke.write_text(smoke.read_text().replace(
        '"file_path": "Midnight/TickLibSpec.lean"',
        '"file_path": "Midnight/TickLibPositiveSpec.lean"',
    ))

    checker = root / "check/check_frozen.py"
    contents = checker.read_text()
    for rel in [*overrides, "check/check_axioms.py", "scripts/check-lean-mcp.py"]:
        digest = hashlib.sha256((root / rel).read_bytes()).hexdigest()
        pattern = rf"('{re.escape(rel)}': ')[0-9a-f]{{64}}(')"
        contents, count = re.subn(pattern, rf"\g<1>{digest}\g<2>", contents)
        if count != 1:
            raise RuntimeError(f"Expected one digest for {rel}, got {count}")
    checker.write_text(contents)


if __name__ == "__main__":
    prepare(Path(sys.argv[1]).resolve())
