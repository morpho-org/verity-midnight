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
`Midnight/Proof.lean` is hashed only at trial start (`check_frozen.py --start`)
so each agent begins from the known stub; the post-proof check allows it to change.

## What counts as done

`./check/check_proof.sh` exits 0. That means:

1. `lake build` succeeds.
2. `Midnight.updatePositionViewProperties` has type `Midnight.Spec.updatePositionViewProperties`.
3. Its axioms are only `propext`, `Classical.choice`, and `Quot.sound`.

`sorry`, `admit`, and extra `axiom`s fail the check. The stub in `Midnight/Proof.lean` fails it.

## Hint

A successful call does not underflow the final checked subtractions, so `newCredit + fee` is the post-slash credit and `newPendingFee + fee` is at most the old pending fee. `lastLossFactor ≤ lossFactor` means slashing multiplies credit by at most one.

Import `Compiler.SolidityImport.Proofs` (and `Compiler.SolidityImport.Access`):
  - functionBody <model>.model "<function>" gets the list of statements in the <function>
  - `splitAfter "<localVar>"` slices the body by Solidity local variable names
  - In case the concrete value of some heavy computation `c` is not needed for the property, `split_prefix`, `split_prefix_continue`, `ends_return`, and `list_frame` (dischargeable `by decide`) step across those slices and frame unmodified bindings accross `c` without executing `c`.
  - `evalExpr_structMember2_param`, `evalExpr_structMember_param`, `sub_word`, `mul_word128`, `div_2ord`, `mask_eq`, and `word_of_small` discharge the storage reads and 256-bit word arithmetic.

lean-lsp MCP (`scripts/lean-mcp.sh`) is required. If it is unavailable, write
`out/mcp-unavailable` and stop (see `AGENTS.md`); do not continue shell-only.

## Loop

```sh
lake build Midnight.Proof
./check/check_proof.sh
```

Work only in this directory. Do not read parent directories or other checkouts.  Do not check the correct answer from github or git history.
