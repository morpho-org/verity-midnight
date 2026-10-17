# Proof: original `TickLib.wExp` is monotonic and total

Proofs of the two frozen statements in `experiment/Midnight/TickLibImportSpec.lean`
(the `wexp-original` task), about the model that `solidity_import` generates from
the unmodified `vendor/midnight/src/libraries/TickLib.sol`:

- `Midnight.Spec.TickLibImport.wExpIsMonotonic`
- `Midnight.Spec.TickLibImport.wExpSucceeds`

Axioms: `propext`, `Classical.choice`, `Quot.sound`. No `sorry`, `native_decide`
or added axioms. The files live outside `experiment/` so that they are not
copied into agent runs.

## Check

```sh
cp -r proofs/wexp-original/Midnight/* experiment/Midnight/
cd experiment
lake build Midnight.WExpProof
lake env lean ../proofs/wexp-original/Check.lean
```

On a machine where the Verity dependency is already built, the build of these
files takes under a minute.

## How it was produced

Claude Opus 5.5 (effort `high`, shell-only Lean, no lean-lsp MCP) proved the same
statements in a task we prepared on Verity `10f697bb`, with the same import
through `certora/helpers/TickLibWrapper.sol`. Porting to this branch only renamed
`inWExpRange` to `inRange` and dropped two unfolds of constants that this spec
inlines. We ran these trials outside the Docker/egress-proxy harness and did not
audit their transcripts with `scripts/audit_transcripts.py`.

| Trial | Proof-phase wall time | Result |
|---|---|---|
| Claude Opus 5.5, trial 1 | 3 h 38 min, on a heavily loaded shared machine | proved |
| Claude Opus 5.5, trial 2 (this proof) | 19 min 37 s | proved |
| Codex `gpt-5.6-sol` | 17 min, then gave up after one `grind` attempt | not proved |

## Proof outline

1. `Exec.lean`: step lemmas for each statement form of the generated body; one
   `simp only` pass runs through the whole imported body.
2. `Word.lean`: each 256-bit operation (add, sub, mul, signed div, shifts,
   unsigned div, signed compare) rewritten as integer arithmetic.
3. `Model.lean`: closed form on the input range,
   `tickLib.wExp o w x = some (ofNat (wd (wexpI x)))`, where `wexpI` is
   `posW x` for `x ≥ 0` and `1e36 / posW (-x)` otherwise.
4. `Math.lean`: the cubic `expR(r)` is non-decreasing in `r` on
   `[-offset, ln2 - offset - 1]`; at a change of `q`, the boundary values satisfy
   `expR(top) = 2 * expR(bottom)` exactly (1447663323139670138 = 2 * 723831661569835069).
5. `WExpProof.lean`: both signs and the crossing at zero (`posW 0 = 1e18`);
   `0 < posW ≤ 1.45e18 * 2^24` rules out reverts and division by zero.
