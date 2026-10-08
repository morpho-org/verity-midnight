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

- A successful call does not underflow the final checked subtractions, so `newCredit + fee` is the post-slash credit and `newPendingFee + fee` is at most the old pending fee. `lastLossFactor ≤ lossFactor` means slashing multiplies credit by at most one. The exact formula for `fee` is not needed.
- Use `import Compiler.SolidityImport.Proofs` (and `Compiler.SolidityImport.Access`):
  - `functionBody midnight.model "updatePositionView"` gets the statement list.
  - `splitAfter "postSlashCredit"`, `splitAfter "postSlashPendingFee"`, and `splitAfter "fee"` slice the body by Solidity local variable names.
  - `split_prefix`, `split_prefix_continue`, `ends_return`, and `list_frame` (dischargeable `by decide`) step across those slices and frame unmodified bindings across `fee` without executing `fee`.
  - `evalExpr_structMember2_param`, `evalExpr_structMember_param`, `sub_word`, `mul_word128`, `div_word`, `mask_eq`, and `word_of_small` discharge the storage reads and 256-bit word arithmetic.

## Loop

```sh
lake build Midnight.Proof
./check/check_proof.sh
```

Work only in this directory. Do not read parent directories or other checkouts. Do not check the correct answer from github or git history.
