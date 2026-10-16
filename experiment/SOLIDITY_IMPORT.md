# Reasoning about `solidity_import` models

`solidity_import` turns Solidity into a deep `CompilationModel` (`<c>.model`),
executed by Verity's `Denote` interpreter, and, for functions whose arguments
are single words, a typed wrapper (`<c>.<fn>`). Other functions are called with
`runFunction <c>.model "<fn>" world args` and read their arguments from
`world.calldata`. Proofs about these models fail mostly for one reason: Lean ends up
*running the interpreter* on a concrete body with symbolic inputs. That makes
terms grow exponentially and exhausts memory, often after minutes and without
a clear error. This guide shows how to avoid that.

## What is already available

- `import ProofKit` (this workspace, prebuilt):
  - `ProofKit/Exec.lean`: step lemmas (`exec_letVar`, `exec_assignVar`,
    `exec_ite`, `exec_panic`, `exec_requireError`, `exec_mstore`,
    `exec_revertReturndata`,
    `exec_returnValues`, `eval_*` including `eval_calldataload`, `eval_mload`,
    the signed `eval_slt`/`eval_sgt`/`eval_sdiv`/`eval_sar`, and `eval_shl`), the `andThen` continuation, `exec_append_andThen`,
    `lookup_bind_same`/`lookup_bind_ne`, `calldataloadWord_aligned`,
    `runFunction_stop`, `runFunction_revertWithData`,
    `runFunction_requireFail`, and the `run_exec` tactic. If you open both
    `ProofKit` and `Compiler.CompilationModel.SolidityImport`, qualify
    `lookup_bind_same`, which both define.
  - `ProofKit/Words.lean`: `wadd`/`wsub`/`wmul`/`wdiv` and their no-wrap
    lemmas (`wadd_of_lt`, `wsub_of_le`, `wmul_of_lt`, `wdiv_of_lt`,
    `wordNormalize_of_lt`).
  - `ProofKit/Signed.lean`: signed (`int256`) words as `Int`. `ofI a` is the
    two's-complement word of `a`; `wadd_ofI`/`wsub_ofI`/`wmul_ofI` make
    wrapping arithmetic `Int` arithmetic modulo `2^256`, `sdiv_ofI` makes
    signed division `Int.tdiv`, `toInt_ofI` reads a word back as `int256`
    (for `eval_slt`/`eval_sgt`), `shl_ofI` turns a small left shift into a
    power of two (`shl_ofI_mul` as an `Int` product), `wordNormalize_eq` turns
    literals into `ofI`, and `ofI_le_ofI`, `ofI_ne_lit`, `wdiv_ofI` and
    `tdiv_cases` handle unsigned comparisons, literal tests, unsigned division
    and truncated division. For signed code, state the run with every word as
    `ofI a` and step it with `run_sexec`, the signed `run_exec`.
- Mathlib is prebuilt. `ProofKit` does not import it: import only the tactic
  modules you use, for example `Mathlib.Tactic.IntervalCases`,
  `Mathlib.Tactic.Ring`, `Mathlib.Tactic.NormNum`, `Mathlib.Tactic.Linarith`,
  and `Mathlib.Tactic.DefEqTransformations` (for `beta_reduce`). Importing all
  of `Mathlib.Tactic` costs about 2 GB more memory in every Lean process and
  MCP worker that loads the file.
- Verity, under `.lake/packages/verity/Compiler/SolidityImport/`:
  - `Coverage.lean`: `rfl` lemmas for every expression and statement form
    the importer emits (`evalExpr_*_arm`, `execStmt_*_arm`).
  - `Access.lean`: `functionBody`, `runFunction`, storage readers, and
    `toWord_*`/`ofWord_*` simp lemmas.
  - `Proofs.lean`: `lookup_bind_same`/`lookup_bind_other`, `splitAfter`,
    `split_prefix`, `list_frame`, `ends_return`, and word lemmas.
  - `../../Contracts/SolidityImportSmoke/`: small worked examples.

## What the importer generates

- `internal` Solidity helpers are inlined into the caller's body.
- A checked operation becomes a `_verity_slice_tmp_N` temporary and an
  `ite` guard that panics on overflow. A body with many checked operations
  has many nested guards.
- A ternary `c ? a : b` becomes `letVar flag c; letVar tmp 0;
  ite flag [assign tmp a] [assign tmp b]`.
- A function whose arguments include a struct, array or `bytes` starts with
  an ABI-decoding prelude: it reads arguments with `calldataload` (argument
  word `i` is at byte `4 + 32 * i`; `calldataloadWord_aligned` turns that into
  `world.calldata.getD i 0`), validates them (`revertReturndata` on bad
  input), and copies structs to memory with `mstore`, reading fields back with
  `mload`. Memory is a function from word addresses: after
  `mstore a v`, `mload a` reads `v` by `if_pos`/`if_neg`.
- A failed check (`panic`) ends in `.revertWithData (panicBytes code)`, not
  `.revert`. `runFunction` maps both to `none`.
- `require(cond, CustomError(args))` becomes `requireError cond "CustomError"
  args`. `exec_requireError` (part of `run_exec`) continues when `cond` holds
  and otherwise ends in `requireFail …`, which `runFunction_requireFail`
  turns into `none`.
- Inspect a body with `#eval functionBody <c>.model "<fn>"` (write a small
  `Stmt` printer if the default output is too long), and cut it at Solidity
  locals with `splitAfter`.

## Rules

1. **Never unfold the interpreter wholesale.** Do not use `simp [execStmtList,
   execStmt, evalExpr]`, `rw [execStmtList]`, `unfold`, `decide` or `rfl` on a
   goal that contains `execStmtList` or `runFunction` over a concrete body
   with symbolic inputs. Use the step lemmas (`run_exec`) instead.

   The same happens indirectly through lemmas proved by `rfl`: `simp` applies
   them without recording a proof step, so the kernel re-checks the result by
   running the interpreter (`(kernel) deep recursion detected` or `excessive
   memory consumption`). Verity's `_arm` lemmas are proved by `rfl`: use them
   with `rw`, not `simp`. Prove your own step lemmas with a real proof (for
   example `by simp only [evalExpr]; rfl`), as `ProofKit` does.

2. **Unfold the typed wrapper at the function level.** `rfl`, `unfold`,
   `delta` or `simp [<c>.<fn>]` applied to `<c>.<fn> o w x` makes the kernel
   evaluate the `runFunction` argument of the generated matcher, which runs the
   whole program. State the unfolding unapplied, reusing the generated
   matcher, and rewrite `runFunction` before any `rfl`:

   ```lean
   theorem fn_fun : <c>.<fn> = fun oracle world x =>
       <c>.<fn>.match_1 (fun _ => Option Uint256)
         (runFunction oracle <c>.model "<fn>" world [("x", Word.toWord x)])
         (fun r => some (Word.ofWord r)) (fun _ => none) := rfl

   -- then: rw [fn_fun]; beta_reduce; rw [toWord_uint256, <your runFunction lemma>]; rfl
   ```

   Check the exact form with `#print <c>.<fn>`; argument names and types
   depend on the function.

   For a `Uint256` result, finish with `Uint256.val_ofNat` and
   `Nat.mod_eq_of_lt` and a bound on the value. `≤` and `<` on `Uint256` are
   definitionally `≤` and `<` on `.val`, so `show a.val ≤ b.val` moves a goal
   to `Nat`.

3. **Connect to `runFunction` through `runFunction_stop`.** It holds for any
   model, so its proof never unfolds `<c>.model`. The run starts from
   `{ world, bindings := args, errors := <c>.model.errors }` with
   `<c>.model.fields`. Prove `hb : functionBody <c>.model "<fn>" = a ++ b` by
   `(List.take_append_drop k _).symm`. Unfold `<c>.model` only to expose the
   statements of a body, never on a goal that still contains `runFunction`.

4. **Generalize the starting state first.** Executing against a concrete
   `DenoteState` literal (`{ world, bindings := [...], errors := ... }`) makes
   definitional checks unfold the record, and they time out at `whnf`. Replace
   it at once:
   `generalize hs : ({ world, bindings := [...], errors := _ } : DenoteState) = s at h`,
   then derive what you need, such as `lookupValue s.bindings "x" = v` or
   `s.world = world`, by `subst hs; rfl`.

5. **Frame instead of execute** when the property does not need a block's
   result, or when a later check already bounds it. For example, if a later
   checked subtraction succeeded, that bounds the value; you need not compute
   it. Verity's `split_prefix`, `list_frame` and `ends_return`
   (`Compiler/SolidityImport/Proofs.lean`) step across such a block and keep
   the bindings it does not modify, without running it. They apply to blocks
   made only of `letVar`, `assignVar`, `ite` and `panic`; a block that writes
   memory or storage (such as an ABI-decoding prelude) has to be executed.

6. **Execute with continuation sharing.** `exec_ite` keeps the `if` inside
   `andThen`, so the rest of the body is shared by both branches. Without it,
   every overflow guard doubles the term. Split long bodies with
   `exec_append_andThen` and prove each part in its own lemma.

7. **Keep bindings folded.** Look past other names with `lookup_bind_ne`; its
   side condition `("a" == "b") = false` is decided by `String.reduceBEq`.
   `run_exec` already discharges side conditions with
   `first | (simp only [String.reduceBEq]; done) | omega`. Reduce numerals in
   a *separate* pass afterwards (`simp only [Nat.reduceMul, Nat.reducePow]`):
   mixing `Nat.reduce*` simprocs into the stepping pass causes heartbeat
   timeouts.

8. **Name intermediate values.** Introduce `Nat` variables with defining
   equations (`hq : (n + c) / d = q`) and their bounds as hypotheses, and pass
   the equations to `run_exec [hq, ...]`. Terms stay small, and `omega`
   discharges the overflow guards (it treats products as atoms; add product
   bounds with `Nat.mul_le_mul`). Case-split on facts a guard needs (for
   example `Nat.eq_zero_or_pos`) before stepping.

9. **When `run_exec` stops early,** find the guard it could not decide. Run it
   on a prefix of the block (or state the block's result as `.revert` for a
   moment) and look at the remaining goal with `lean_goal`. The first
   `andThen` that was not stepped holds the `ite` whose side condition
   `omega` could not prove. Add the missing fact (a case split such as
   `Nat.eq_zero_or_pos` before a checked `mul`, or a bound) and run again.
   Use `run_exec [...] at h` to step a hypothesis instead of the goal.

10. **Architecture.** Imported model → step lemmas → one bridge lemma
   `<c>.<fn> o w x = some (Uint256.ofNat (ref x.val))` for the whole input range
   → all mathematics on a plain-`Nat` reference function `ref`. A "succeeds"
   property then follows from the bridge directly. To show such a function
   is monotone, prove the one-step lemma `ref x ≤ ref (x + 1)` and lift it by
   induction (`monotone_nat_of_le_succ`). For floored terms, bound the change
   per step instead of reasoning about real functions; at piecewise
   boundaries, check the values on both sides exactly.

11. **Keep modules small.** Put heavy execution lemmas in separate modules and
   measure each one's peak with `leanrun` before composing them; keep each
   well under the cap. Importing the task's model and `ProofKit` alone takes
   about 1.5–2 GB. Large `simp` proof terms are also stored in the `.olean`,
   so `lake build` can need more memory than the editor did.

12. **Do the numbers first.** Before choosing a proof strategy, evaluate the
   function at its boundaries and extremes (in Python, or with `#eval` on a
   reference function). Exactly tight points mean a uniform bound will not
   work and exact reasoning is needed there.

## Tools and memory

The container has about 15 GB of memory for everything, with no headroom.

- **Lean's memory cap.** Every Lean process (`lake build`, `lake env lean`,
  MCP workers) runs with `-M $LEAN_MEMORY_MB` (default 6144 MB). A runaway
  proof then fails with `excessive memory consumption detected` instead of
  being killed. Raise the cap for one command only when a module really needs
  it (`LEAN_MEMORY_MB=9000 lake build X`); `LEAN_MEMORY_MB=0` disables it.
- **`leanrun`.** `leanrun Midnight/Lemmas/Foo.lean` (or `leanrun lake build X`)
  runs the command and prints `exit=… peak_rss=… wall=…` to stderr, with a
  verdict. Use it to measure modules and to see failures a pipe would hide.
- **Exit status 137** means the OOM killer stopped the process, not a Lean
  error. MCP's "file worker died … stack overflow?" usually means the same.
  `cmd | head` reports `head`'s status: use `set -o pipefail` or `leanrun`.
- **Probe risky tactics cheaply** under `set_option maxHeartbeats 20000 in`.
  Kernel checks respect it too, so you get a fast timeout instead of a slow
  out-of-memory failure. To locate a timeout, close the proof early with
  `sorry`, inspect the goal with `lean_goal`, and try a few variants at once
  with `lean_multi_attempt`.
- **MCP workers** keep up to 2 files open (about 2 GB each). Before a large
  `lake build`, stop working on big files in MCP, so the build has memory.
