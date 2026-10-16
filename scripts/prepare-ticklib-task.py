#!/usr/bin/env python3
"""Select the nine TickLib rules (wExp and tickToPrice) on the original imported Solidity."""

import hashlib
from pathlib import Path
import re
import runpy
import sys


def prepare(root: Path) -> None:
    base = runpy.run_path(str(Path(__file__).with_name("prepare-wexp-task.py")))
    base["prepare"](root)
    overrides = {
        "Midnight/Proof.lean": """import Midnight.TickLibFullSpec

namespace Midnight.TickLibFull

theorem wExpIsMonotonic : Spec.TickLibFull.wExpIsMonotonic := by
  sorry

theorem wExpNotMonotonicBeyond : Spec.TickLibFull.wExpNotMonotonicBeyond := by
  sorry

theorem maxOutputIsWExpOfMaxInput : Spec.TickLibFull.maxOutputIsWExpOfMaxInput := by
  sorry

theorem tickToPriceIsMonotonic : Spec.TickLibFull.tickToPriceIsMonotonic := by
  sorry

theorem tickToPriceIsZeroAtZero : Spec.TickLibFull.tickToPriceIsZeroAtZero := by
  sorry

theorem tickToPriceIsOneAtMaxTick : Spec.TickLibFull.tickToPriceIsOneAtMaxTick := by
  sorry

theorem tickToPriceUsesPriceRoundingStep : Spec.TickLibFull.tickToPriceUsesPriceRoundingStep := by
  sorry

theorem tickToPriceAtMostWad : Spec.TickLibFull.tickToPriceAtMostWad := by
  sorry

theorem tickToPriceTotal : Spec.TickLibFull.tickToPriceTotal := by
  sorry

end Midnight.TickLibFull
""",
        "Midnight.lean": """import Midnight.TickLibFullSpec
import Midnight.Proof
""",
        "check/Goal.lean": """import Midnight

-- Every claim must be proved about the exact imported model.
example : Midnight.Spec.TickLibFull.wExpIsMonotonic := Midnight.TickLibFull.wExpIsMonotonic
example : Midnight.Spec.TickLibFull.wExpNotMonotonicBeyond := Midnight.TickLibFull.wExpNotMonotonicBeyond
example : Midnight.Spec.TickLibFull.maxOutputIsWExpOfMaxInput := Midnight.TickLibFull.maxOutputIsWExpOfMaxInput
example : Midnight.Spec.TickLibFull.tickToPriceIsMonotonic := Midnight.TickLibFull.tickToPriceIsMonotonic
example : Midnight.Spec.TickLibFull.tickToPriceIsZeroAtZero := Midnight.TickLibFull.tickToPriceIsZeroAtZero
example : Midnight.Spec.TickLibFull.tickToPriceIsOneAtMaxTick := Midnight.TickLibFull.tickToPriceIsOneAtMaxTick
example : Midnight.Spec.TickLibFull.tickToPriceUsesPriceRoundingStep := Midnight.TickLibFull.tickToPriceUsesPriceRoundingStep
example : Midnight.Spec.TickLibFull.tickToPriceAtMostWad := Midnight.TickLibFull.tickToPriceAtMostWad
example : Midnight.Spec.TickLibFull.tickToPriceTotal := Midnight.TickLibFull.tickToPriceTotal

#print axioms Midnight.TickLibFull.wExpIsMonotonic
#print axioms Midnight.TickLibFull.wExpNotMonotonicBeyond
#print axioms Midnight.TickLibFull.maxOutputIsWExpOfMaxInput
#print axioms Midnight.TickLibFull.tickToPriceIsMonotonic
#print axioms Midnight.TickLibFull.tickToPriceIsZeroAtZero
#print axioms Midnight.TickLibFull.tickToPriceIsOneAtMaxTick
#print axioms Midnight.TickLibFull.tickToPriceUsesPriceRoundingStep
#print axioms Midnight.TickLibFull.tickToPriceAtMostWad
#print axioms Midnight.TickLibFull.tickToPriceTotal
#print axioms tickLibFull.covered
""",
        "README.md": """# Prove the TickLib rules on the original Solidity

Prove all nine frozen statements in `Midnight/TickLibFullSpec.lean` about
Midnight's original `TickLib.wExp` and `TickLib.tickToPrice`:

1. `wExpIsMonotonic`: on `[-xStar, xStar]`, `xStar = 135999161806159974428`,
   both calls succeed and `x <= y` implies `wExp(x) <= wExp(y)`.
2. `wExpNotMonotonicBeyond`: `wExp(xStar) > wExp(xStar + 1) = 0`.
3. `maxOutputIsWExpOfMaxInput`: `wExp(maxInput) == maxOutput`.
4. `tickToPriceIsMonotonic`: for successful calls, `tick1 < tick2` implies
   `tickToPrice(tick1) <= tickToPrice(tick2)`, using the real `wExp` (no
   summary).
5. `tickToPriceIsZeroAtZero`, 6. `tickToPriceIsOneAtMaxTick`,
7. `tickToPriceUsesPriceRoundingStep`, 8. `tickToPriceAtMostWad`: the
   `TickToPrice.spec` rules, on successful calls.
9. `tickToPriceTotal`: every `tick <= MAX_TICK` succeeds.

The docstring of `Midnight/TickLibFullSpec.lean` explains how they relate to
the Certora rules in `vendor/midnight/certora/specs/TickToPrice*.spec`.

`Midnight/TickLibFullImport.lean` uses `solidity_import` to generate
`tickLibFull.model`, `tickLibFull.wExp` and `tickLibFull.tickToPrice` from
Midnight's unmodified `vendor/midnight/src/libraries/TickLib.sol`, through the
Certora harness `vendor/midnight/certora/helpers/TickLibWrapper.sol`. Reason
about that generated model. `wExp` uses unchecked signed (`int256`)
arithmetic, signed division, a left shift and a recursive call for negative
inputs (`wExp(x) = 1e36 / wExp(-x)`), which the importer inlines; `tickToPrice`
inlines `wExp` and two rounding divisions. `check/TickLibFullSmoke.lean` runs
both on concrete inputs.

Read `SOLIDITY_IMPORT.md` before your first proof attempt: it explains how to
run the imported body symbolically without exhausting memory, and the prebuilt
`ProofKit` lemmas (`import ProofKit`, including `ProofKit.Signed` for `int256`
words) that do it.

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
imported model or weaken any statement or its input range.

## What counts as done

`./check/check_proof.sh` exits 0. It checks the frozen files, builds the
library, checks all nine theorem types, and audits every proof and
`tickLibFull.covered`. Only `propext`, `Classical.choice`, and `Quot.sound`
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
        '"Midnight.TickLibFull.wExpIsMonotonic",\n    "Midnight.TickLibFull.wExpNotMonotonicBeyond",\n    "Midnight.TickLibFull.maxOutputIsWExpOfMaxInput",\n    "Midnight.TickLibFull.tickToPriceIsMonotonic",\n    "Midnight.TickLibFull.tickToPriceIsZeroAtZero",\n    "Midnight.TickLibFull.tickToPriceIsOneAtMaxTick",\n    "Midnight.TickLibFull.tickToPriceUsesPriceRoundingStep",\n    "Midnight.TickLibFull.tickToPriceAtMostWad",\n    "Midnight.TickLibFull.tickToPriceTotal",\n    "tickLibFull.covered",',
    )
    axioms.write_text(contents)
    smoke = root / "scripts/check-lean-mcp.py"
    smoke.write_text(smoke.read_text().replace(
        '"file_path": "Midnight/TickLibSpec.lean"',
        '"file_path": "Midnight/TickLibFullSpec.lean"',
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
