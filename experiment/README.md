# Prove `updatePositionViewProperties`

`Midnight/Spec.lean` states the Certora rule `updatePositionViewProperties` on the Solidity imported by `Midnight/Import.lean`. `Midnight/Proof.lean` does not prove it yet.

Produce a proof that `./check/check_proof.sh` accepts.

## What you may edit

- `Midnight/Proof.lean`
- new files under `Midnight/`, including `Midnight/Lemmas/`

## What you may not edit

- `Midnight/Import.lean`, `Midnight/Spec.lean`, `Midnight.lean`
- `lakefile.lean`, `lake-manifest.json`, `lean-toolchain`
- `vendor/`
- `check/`

The checker hashes those files and rejects the run if they change.

## What counts as done

`./check/check_proof.sh` exits 0. That means:

1. `lake build` succeeds.
2. `Midnight.updatePositionViewProperties` has type `Midnight.Spec.updatePositionViewProperties`.
3. Its axioms are only `propext`, `Classical.choice`, and `Quot.sound`.

`sorry`, `admit`, and extra `axiom`s fail the check. The stub in `Midnight/Proof.lean` fails it.

## Hint

A successful call does not underflow the final checked subtractions, so `newCredit + fee` is the post-slash credit and `newPendingFee + fee` is at most the old pending fee. `lastLossFactor ≤ lossFactor` means slashing multiplies credit by at most one.

Import `Compiler.SolidityImport.Proofs` for word/bind lemmas and for cutting the imported body at Solidity local names.

Use lean-lsp MCP (`scripts/lean-mcp.sh`) for diagnostics, goals, hover, and local search.

## Loop

```sh
lake build Midnight.Proof
./check/check_proof.sh
```

Work only in this directory. Do not read parent directories or other checkouts.  Do not check the correct answer from github.
