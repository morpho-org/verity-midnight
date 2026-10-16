# Unsigned positive exponential

`TickLibPositive.sol` is a non-recursive unsigned rewrite of the original
`TickLib.wExp` on `0 <= x <= 16817989975223754156`, the nonnegative input range
used by `tickToPrice`.

The residual can be negative even for positive `x`. The rewrite stores its
magnitude and branches when assembling the polynomial, preserving the original
signed division's truncation toward zero. It uses checked arithmetic; the
intended range is chosen so that the original intermediate operations do not
overflow either.

The pinned importer supports neither shifts nor exponentiation. The `pow2`
helper expresses the shift factor through conditional multiplications. It is
exact for `q <= 31`, covering `q <= 24` on the intended input range. Behavior
outside that input range is not part of this implementation's specification.

`Midnight/TickLibPositiveImport.lean` uses Verity's `solidity_import` to generate
the Lean model and typed `tickLibPositive.wExp` accessor from this Solidity.
`Midnight/TickLibPositiveSpec.lean` states successful-call monotonicity and
success for all inputs in range. These are specifications awaiting proofs.
The importer remains part of the trust base, as in `Midnight/Import.lean`.

With the project's pinned Lean dependencies and solc 0.8.34 installed:

```sh
lake build Midnight.TickLibPositiveSpec
lake env lean check/TickLibPositiveSmoke.lean
```

From the repository root, Foundry can compare actual EVM execution of the two
Solidity implementations:

```sh
FOUNDRY_TEST=solidity/test forge test --root experiment --contracts solidity \
  --use 0.8.34 --evm-version osaka --via-ir --optimize --optimizer-runs 466 \
  --fuzz-runs 4096
```

The tests cover all 3373 positive tick inputs, both sides of every in-range
segment jump and residual-sign boundary, the endpoints, and random inputs.
They provide differential test evidence; equivalence to the original signed
implementation has not been formally proved.
