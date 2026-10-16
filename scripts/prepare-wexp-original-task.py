#!/usr/bin/env python3
"""Select the task on Midnight's original imported signed exponential in a fresh run."""

import hashlib
from pathlib import Path
import re
import runpy
import sys


def prepare(root: Path) -> None:
    base = runpy.run_path(str(Path(__file__).with_name("prepare-wexp-task.py")))
    base["prepare"](root)
    overrides = {
        "Midnight/Proof.lean": """import Midnight.TickLibImportSpec

namespace Midnight.TickLibImport

theorem wExpIsMonotonic : Spec.TickLibImport.wExpIsMonotonic := by
  sorry

theorem wExpSucceeds : Spec.TickLibImport.wExpSucceeds := by
  sorry

end Midnight.TickLibImport
""",
        "Midnight.lean": """import Midnight.TickLibImportSpec
import Midnight.Proof
""",
        "check/Goal.lean": """import Midnight

-- Both claims must be proved about the exact imported model.
example : Midnight.Spec.TickLibImport.wExpIsMonotonic :=
  Midnight.TickLibImport.wExpIsMonotonic
example : Midnight.Spec.TickLibImport.wExpSucceeds :=
  Midnight.TickLibImport.wExpSucceeds

#print axioms Midnight.TickLibImport.wExpIsMonotonic
#print axioms Midnight.TickLibImport.wExpSucceeds
#print axioms tickLib.covered
""",
        "README.md": """# Prove monotonicity of Midnight's original `wExp`

Prove both frozen statements in `Midnight/TickLibImportSpec.lean`:

1. `Midnight.Spec.TickLibImport.wExpIsMonotonic`: for signed inputs
   `y < x` in `[-maxInput, maxInput]`, successful outputs satisfy
   `wExp(y) <= wExp(x)`.
2. `Midnight.Spec.TickLibImport.wExpSucceeds`: every input in that range
   succeeds, ruling out vacuous monotonicity caused by reverts.

`Midnight/TickLibImport.lean` uses `solidity_import` to generate `tickLib.model`
and `tickLib.wExp` from Midnight's unmodified
`vendor/midnight/src/libraries/TickLib.sol`, through the Certora harness
`vendor/midnight/certora/helpers/TickLibWrapper.sol`. Reason about that
generated model. The Solidity uses unchecked signed (`int256`) arithmetic,
signed division, a left shift, and a recursive call for negative inputs
(`wExp(x) = 1e36 / wExp(-x)`), which the importer inlines. The range is
`maxInput = LN_ONE_PLUS_DELTA * (MAX_TICK / 2) = 16817989975223754156`.

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

The Solidity, the import and the specification are frozen. Do not replace the
imported model or weaken either statement or its input range.

## What counts as done

`./check/check_proof.sh` exits 0. It checks the frozen files, builds the
library, checks both theorem types, and audits both proofs and
`tickLib.covered`. Only `propext`, `Classical.choice`, and `Quot.sound`
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
        '"Midnight.TickLibImport.wExpIsMonotonic",\n'
        '    "Midnight.TickLibImport.wExpSucceeds",\n'
        '    "tickLib.covered",',
    )
    axioms.write_text(contents)
    smoke = root / "scripts/check-lean-mcp.py"
    smoke.write_text(smoke.read_text().replace(
        '"file_path": "Midnight/TickLibSpec.lean"',
        '"file_path": "Midnight/TickLibImportSpec.lean"',
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
