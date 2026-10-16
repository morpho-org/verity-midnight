import ProofKit.Words

/-!
# Step lemmas for symbolic execution of imported models

Use these with `simp only` (or the `run_exec` tactic below) to execute an
imported body one statement at a time, instead of unfolding `execStmtList`,
`execStmt` or `evalExpr`. Unfolding the interpreter on a concrete body with
symbolic inputs makes terms grow exponentially and exhausts memory.

* `andThen` is the continuation of `execStmtList` after one statement.
  `exec_ite` keeps the `if` *inside* `andThen`, so the rest of the body is
  shared by both branches rather than copied into each of them. Checked
  arithmetic produces a guard `ite` per operation, so this sharing matters.
* `eval_*` restate the `evalExpr` arms with plain-`Nat` word operations
  (`ProofKit.wadd` etc.); `wadd_of_lt` etc. then remove the wrapping.
  They are deliberately not proved by `rfl`: `simp` applies a lemma proved by
  `rfl` without recording a proof step, which leaves the kernel to re-check the
  result by running the interpreter, and that exhausts memory.
* `ProofKit` imports no Mathlib (each Lean process that imports all of
  `Mathlib.Tactic` needs about 2 GB more memory); import the tactic modules a
  proof needs individually.
* `lookup_bind_ne` has a `Bool` side condition that `String.reduceBEq` decides,
  so bindings stay a folded `bindValue` chain.
* `exec_append_andThen` splits a body; `runFunction_stop` connects a run of the
  body to `runFunction` for any model and function name.
-/

open Compiler.CompilationModel Compiler.CompilationModel.Denote
open Compiler.CompilationModel.SolidityImport
open Verity.Core

namespace ProofKit

/-- Continue a statement list after the outcome `r` of one statement. -/
def andThen (oracle : DenoteOracle) (fields : List Field) (r : StmtOutcome)
    (rest : List Stmt) : StmtOutcome :=
  match r with
  | .continue next => execStmtList oracle fields next rest
  | .stop next => .stop next
  | .return value next => .return value next
  | .revert => .revert
  | .revertWithData data => .revertWithData data

section
variable {oracle : DenoteOracle} {fields : List Field} {s : DenoteState}

theorem andThen_continue (s' : DenoteState) (rest : List Stmt) :
    andThen oracle fields (.continue s') rest = execStmtList oracle fields s' rest := rfl

theorem andThen_revert (rest : List Stmt) :
    andThen oracle fields .revert rest = .revert := rfl

theorem andThen_stop (s' : DenoteState) (rest : List Stmt) :
    andThen oracle fields (.stop s') rest = .stop s' := rfl

theorem andThen_return (v : Nat) (s' : DenoteState) (rest : List Stmt) :
    andThen oracle fields (.return v s') rest = .return v s' := rfl

theorem andThen_revertWithData (data : List UInt8) (rest : List Stmt) :
    andThen oracle fields (.revertWithData data) rest = .revertWithData data := rfl

theorem exec_nil : execStmtList oracle fields s [] = .continue s := by
  rw [execStmtList.eq_1]

theorem exec_cons (st : Stmt) (rest : List Stmt) :
    execStmtList oracle fields s (st :: rest) =
      andThen oracle fields (execStmt oracle fields s st) rest := by
  rw [execStmtList.eq_2]; rfl

theorem exec_letVar (name : String) (value : Expr) (rest : List Stmt) :
    execStmtList oracle fields s (.letVar name value :: rest) =
      match evalExpr oracle fields s value with
      | some v => execStmtList oracle fields
          { s with bindings := bindValue s.bindings name v } rest
      | none => .revert := by
  rw [exec_cons, execStmt_letVar_arm]
  cases evalExpr oracle fields s value <;> rfl

theorem exec_assignVar (name : String) (value : Expr) (rest : List Stmt) :
    execStmtList oracle fields s (.assignVar name value :: rest) =
      match evalExpr oracle fields s value with
      | some v => execStmtList oracle fields
          { s with bindings := bindValue s.bindings name v } rest
      | none => .revert := by
  rw [exec_cons, execStmt_assignVar_arm]
  cases evalExpr oracle fields s value <;> rfl

/-- A failed checked operation panics: the call reverts with the panic payload. -/
theorem exec_panic (c : PanicCode) (rest : List Stmt) :
    execStmtList oracle fields s (.panic c :: rest) = .revertWithData (panicBytes c.toNat) := by
  rw [exec_cons, execStmt_panic_arm]; rfl

/-- The `if` stays inside `andThen`: `rest` appears once, not once per branch. -/
theorem exec_ite (c : Expr) (t e rest : List Stmt) :
    execStmtList oracle fields s (.ite c t e :: rest) =
      match evalExpr oracle fields s c with
      | some v =>
          andThen oracle fields
            (if v != 0 then execStmtList oracle fields s t
             else execStmtList oracle fields s e) rest
      | none => .revert := by
  rw [exec_cons, execStmt_ite_arm]
  cases evalExpr oracle fields s c <;> rfl

/-- What a failing `require(cond, CustomError(args))` returns: the encoded error,
or a plain revert when its arguments or the error definition cannot be resolved. -/
def requireFail (oracle : DenoteOracle) (fields : List Field) (s : DenoteState)
    (name : String) (args : List Expr) : StmtOutcome :=
  match evalExprList oracle fields s args with
  | none => .revert
  | some values => match customErrorBytes oracle s.errors name values with
      | some bytes => .revertWithData bytes
      | none => .revert

/-- `require(cond, CustomError(args))`: continue when `cond` holds, otherwise revert. -/
theorem exec_requireError (c : Expr) (name : String) (args : List Expr) (rest : List Stmt) :
    execStmtList oracle fields s (.requireError c name args :: rest) =
      match evalExpr oracle fields s c with
      | some v => if v != 0 then execStmtList oracle fields s rest
          else requireFail oracle fields s name args
      | none => .revert := by
  rw [exec_cons, execStmt_requireError_arm]
  cases evalExpr oracle fields s c with
  | none => rfl
  | some v =>
    simp only
    split
    · rfl
    · unfold requireFail
      cases evalExprList oracle fields s args with
      | none => rfl
      | some vs =>
        simp only
        cases customErrorBytes oracle s.errors name vs <;> rfl

/-- ABI decoding failures revert with the (usually empty) return data. -/
theorem exec_revertReturndata (rest : List Stmt) :
    execStmtList oracle fields s (.revertReturndata :: rest) =
      .revertWithData (s.world.returndata.flatMap wordBytes) := by
  rw [exec_cons, execStmt_revertReturndata_arm]; rfl

/-- `mstore` writes one word of `s.world.memory`. -/
theorem exec_mstore (offset value : Expr) (rest : List Stmt) :
    execStmtList oracle fields s (.mstore offset value :: rest) =
      match evalExpr oracle fields s offset, evalExpr oracle fields s value with
      | some a, some v => execStmtList oracle fields
          { s with world := { s.world with
              memory := fun o => if o = a then v else s.world.memory o } } rest
      | _, _ => .revert := by
  rw [exec_cons, execStmt_mstore_arm]
  cases evalExpr oracle fields s offset <;> cases evalExpr oracle fields s value <;> rfl

theorem exec_returnValues (values : List Expr) (rest : List Stmt) :
    execStmtList oracle fields s (.returnValues values :: rest) =
      match evalExprList oracle fields s values with
      | some vs => .stop { s with observedReturnWords := some (vs.map wordNormalize),
                                  observedStop := false }
      | none => .revert := by
  rw [exec_cons, execStmt_returnValues_arm]
  cases evalExprList oracle fields s values <;> rfl

theorem evalExprList_cons (e : Expr) (es : List Expr) :
    evalExprList oracle fields s (e :: es) =
      (evalExpr oracle fields s e).bind fun v =>
        (evalExprList oracle fields s es).bind fun vs => some (v :: vs) := by
  rw [evalExprList]; rfl

theorem evalExprList_nil : evalExprList oracle fields s [] = some [] := by
  rw [evalExprList]

theorem eval_literal (n : Nat) :
    evalExpr oracle fields s (.literal n) = some (wordNormalize n) := by
  simp only [evalExpr]

theorem eval_param (name : String) :
    evalExpr oracle fields s (.param name) = some (lookupValue s.bindings name) := by
  simp only [evalExpr]

theorem eval_localVar (name : String) :
    evalExpr oracle fields s (.localVar name) = some (lookupValue s.bindings name) := by
  simp only [evalExpr]

theorem eval_add (a b : Expr) :
    evalExpr oracle fields s (.add a b) =
      (evalExpr oracle fields s a).bind fun x =>
        (evalExpr oracle fields s b).bind fun y => some (wadd x y) := by
  simp only [evalExpr]; rfl

theorem eval_sub (a b : Expr) :
    evalExpr oracle fields s (.sub a b) =
      (evalExpr oracle fields s a).bind fun x =>
        (evalExpr oracle fields s b).bind fun y => some (wsub x y) := by
  simp only [evalExpr]; rfl

theorem eval_mul (a b : Expr) :
    evalExpr oracle fields s (.mul a b) =
      (evalExpr oracle fields s a).bind fun x =>
        (evalExpr oracle fields s b).bind fun y => some (wmul x y) := by
  simp only [evalExpr]; rfl

theorem eval_div (a b : Expr) :
    evalExpr oracle fields s (.div a b) =
      (evalExpr oracle fields s a).bind fun x =>
        (evalExpr oracle fields s b).bind fun y => some (wdiv x y) := by
  simp only [evalExpr]; rfl

theorem eval_eq (a b : Expr) :
    evalExpr oracle fields s (.eq a b) =
      (evalExpr oracle fields s a).bind fun x =>
        (evalExpr oracle fields s b).bind fun y => some (boolWord (decide (x = y))) := by
  simp only [evalExpr]; rfl

theorem eval_lt (a b : Expr) :
    evalExpr oracle fields s (.lt a b) =
      (evalExpr oracle fields s a).bind fun x =>
        (evalExpr oracle fields s b).bind fun y => some (boolWord (decide (x < y))) := by
  simp only [evalExpr]; rfl

theorem eval_gt (a b : Expr) :
    evalExpr oracle fields s (.gt a b) =
      (evalExpr oracle fields s a).bind fun x =>
        (evalExpr oracle fields s b).bind fun y => some (boolWord (decide (y < x))) := by
  simp only [evalExpr]; rfl

theorem eval_le (a b : Expr) :
    evalExpr oracle fields s (.le a b) =
      (evalExpr oracle fields s a).bind fun x =>
        (evalExpr oracle fields s b).bind fun y => some (boolWord (decide (x ≤ y))) := by
  simp only [evalExpr]; rfl

theorem eval_ge (a b : Expr) :
    evalExpr oracle fields s (.ge a b) =
      (evalExpr oracle fields s a).bind fun x =>
        (evalExpr oracle fields s b).bind fun y => some (boolWord (decide (y ≤ x))) := by
  simp only [evalExpr]; rfl

theorem eval_calldataload (a : Expr) :
    evalExpr oracle fields s (.calldataload a) =
      (evalExpr oracle fields s a).bind fun o =>
        some (calldataloadWord s.selector s.world.calldata o) := by
  simp only [evalExpr]; rfl

theorem eval_calldatasize :
    evalExpr oracle fields s .calldatasize = some s.world.calldataSize.val := by
  simp only [evalExpr]

theorem eval_mload (a : Expr) :
    evalExpr oracle fields s (.mload a) =
      (evalExpr oracle fields s a).bind fun o => some (s.world.memory o).val := by
  simp only [evalExpr]; rfl

/-- Signed comparison: both words are read as two's-complement `int256`. -/
theorem eval_slt (a b : Expr) :
    evalExpr oracle fields s (.slt a b) =
      (evalExpr oracle fields s a).bind fun x =>
        (evalExpr oracle fields s b).bind fun y =>
          some (boolWord (decide ((Int256.ofUint256 (Uint256.ofNat x) : Int) <
            (Int256.ofUint256 (Uint256.ofNat y) : Int)))) := by
  simp only [evalExpr]; rfl

/-- Signed division (`sdiv`): both words are read as `int256`; rounds toward zero. -/
theorem eval_sdiv (a b : Expr) :
    evalExpr oracle fields s (.sdiv a b) =
      (evalExpr oracle fields s a).bind fun x =>
        (evalExpr oracle fields s b).bind fun y =>
          some (Int256.div (Int256.ofUint256 (Uint256.ofNat x))
            (Int256.ofUint256 (Uint256.ofNat y))).toUint256.val := by
  simp only [evalExpr]; rfl

theorem eval_sgt (a b : Expr) :
    evalExpr oracle fields s (.sgt a b) =
      (evalExpr oracle fields s a).bind fun x =>
        (evalExpr oracle fields s b).bind fun y =>
          some (boolWord (decide ((Int256.ofUint256 (Uint256.ofNat y) : Int) <
            (Int256.ofUint256 (Uint256.ofNat x) : Int)))) := by
  simp only [evalExpr]; rfl

/-- `shl shift value`: a shift of 256 or more gives 0. -/
theorem eval_shl (a b : Expr) :
    evalExpr oracle fields s (.shl a b) =
      (evalExpr oracle fields s a).bind fun k =>
        (evalExpr oracle fields s b).bind fun w =>
          some (Uint256.shl (Uint256.ofNat k) (Uint256.ofNat w)).val := by
  simp only [evalExpr]; rfl

theorem eval_sar (a b : Expr) :
    evalExpr oracle fields s (.sar a b) =
      (evalExpr oracle fields s a).bind fun x =>
        (evalExpr oracle fields s b).bind fun y =>
          some (Int256.sar (Int256.ofUint256 (Uint256.ofNat x))
            (Int256.ofUint256 (Uint256.ofNat y))).toUint256.val := by
  simp only [evalExpr]; rfl

theorem eval_logicalNot (a : Expr) :
    evalExpr oracle fields s (.logicalNot a) =
      (evalExpr oracle fields s a).bind fun x => some (boolWord (decide (x = 0))) := by
  simp only [evalExpr]; rfl

end

/-! ## Bindings -/

theorem lookup_bind_same (b : Env) (n : String) (v : Nat) :
    lookupValue (bindValue b n v) n = v := by
  simp [lookupValue, bindValue]

theorem find_filter_ne (b : Env) (n m : String) (h : (m == n) = false) :
    (b.filter (fun entry => entry.1 != n)).find? (fun entry => entry.1 == m) =
      b.find? (fun entry => entry.1 == m) := by
  induction b with
  | nil => rfl
  | cons hd tl ih =>
    rw [List.filter_cons]
    by_cases hn : hd.1 = n
    · have h1 : (hd.1 != n) = false := by rw [hn]; exact bne_self_eq_false n
      have h2 : (hd.1 == m) = false := by
        rw [hn]; cases hnm : (n == m)
        · rfl
        · rw [beq_iff_eq] at hnm; subst hnm; rw [beq_self_eq_true] at h; exact h
      rw [h1, if_neg Bool.false_ne_true, ih, List.find?_cons, h2]
    · have h1 : (hd.1 != n) = true := by
        rw [bne_iff_ne]; exact hn
      rw [h1, if_pos rfl, List.find?_cons, List.find?_cons, ih]

/-- Look past a binding of another name. `String.reduceBEq` decides `h` for
literal names, so `simp` can use this as a rewrite with a discharger. -/
theorem lookup_bind_ne (b : Env) (n m : String) (v : Nat) (h : (m == n) = false) :
    lookupValue (bindValue b n v) m = lookupValue b m := by
  unfold lookupValue bindValue
  have h' : ((n, v).1 == m) = false := by
    show (n == m) = false
    cases hnm : (n == m)
    · rfl
    · rw [beq_iff_eq] at hnm; subst hnm; rw [beq_self_eq_true] at h; exact h
  rw [List.find?_cons, h', find_filter_ne b n m h]

theorem lookup_single (n : String) (v : Nat) : lookupValue [(n, v)] n = v := by
  simp [lookupValue]

/-! ## Call data -/

/-- A word-aligned `calldataload` reads one call-data word (the selector
occupies bytes 0–3, so argument word `i` is at byte `4 + 32 * i`). -/
theorem calldataloadWord_aligned (sel : Nat) (cd : List Nat) (i : Nat) :
    calldataloadWord sel cd (4 + 32 * i) = cd.getD i 0 % 2 ^ 256 := by
  unfold calldataloadWord
  have h1 : (4 + 32 * i = 0) = False := by simp
  have h2 : (4 + 32 * i < 4) = False := by simp
  simp only [h1, h2, if_false, Nat.add_sub_cancel_left, Nat.mul_mod_right, if_true,
    Nat.mul_div_cancel_left _ (by decide : 0 < 32)]

/-! ## Splitting and running a body -/

/-- Split a body; the second part runs only if the first one continues. -/
theorem exec_append_andThen {oracle : DenoteOracle} {fields : List Field} (s : DenoteState)
    (a b : List Stmt) :
    execStmtList oracle fields s (a ++ b) =
      andThen oracle fields (execStmtList oracle fields s a) b := by
  induction a generalizing s with
  | nil => rw [exec_nil]; rfl
  | cons st rest ih =>
    rw [List.cons_append, exec_cons, exec_cons]
    unfold andThen
    cases execStmt oracle fields s st with
    | «continue» next => exact ih next
    | stop next => rfl
    | «return» v next => rfl
    | revert => rfl
    | revertWithData data => rfl

/-- Connect a run of a function body to `runFunction`, for any model. State
`hb` with the body split as you need it (for example
`(List.take_append_drop k _).symm`). Do not unfold the generated `model` with
`simp`. -/
theorem runFunction_stop (oracle : DenoteOracle) (model : CompilationModel) (fn : String)
    (world : Verity.ContractState) (args : Env) (body : List Stmt) (s' : DenoteState)
    (hb : functionBody model fn = body)
    (h : execStmtList oracle model.fields { world, bindings := args, errors := model.errors }
      body = .stop s') :
    runFunction oracle model fn world args = s'.observedReturnWords := by
  unfold runFunction
  rw [hb, h]

/-- A failing `require` makes `runFunction` return `none`. -/
theorem runFunction_requireFail (oracle : DenoteOracle) (model : CompilationModel)
    (fn : String) (world : Verity.ContractState) (args : Env) (name : String)
    (eargs : List Expr) (s : DenoteState)
    (h : execStmtList oracle model.fields { world, bindings := args, errors := model.errors }
      (functionBody model fn) = requireFail oracle model.fields s name eargs) :
    runFunction oracle model fn world args = none := by
  unfold runFunction
  rw [h]
  unfold requireFail
  cases evalExprList oracle model.fields s eargs with
  | none => rfl
  | some vs =>
    simp only
    cases customErrorBytes oracle s.errors name vs <;> rfl

/-- A run that reverts makes `runFunction` return `none`. -/
theorem runFunction_revertWithData (oracle : DenoteOracle) (model : CompilationModel)
    (fn : String) (world : Verity.ContractState) (args : Env) (body : List Stmt)
    (data : List UInt8) (hb : functionBody model fn = body)
    (h : execStmtList oracle model.fields { world, bindings := args, errors := model.errors }
      body = .revertWithData data) :
    runFunction oracle model fn world args = none := by
  unfold runFunction
  rw [hb, h]

/-! ## `run_exec`

`run_exec` steps through straight-line code with all of the lemmas above. Side
conditions (branch guards, no-wrap bounds, distinct names) are discharged by
`String.reduceBEq` or `omega` from hypotheses in the context, so introduce named
intermediate values and their bounds first. Pass extra rewrite lemmas, such as
defining equations of named values, in brackets: `run_exec [hq, hm]`. To run
code inside a hypothesis instead of the goal, add a location, as for `simp`:
`run_exec [hq] at h`.

Reduce numerals in a separate pass afterwards (for example
`simp only [Nat.reduceMul, Nat.reduceAdd]`): mixing `Nat.reduce*` simprocs
into the stepping pass causes heartbeat timeouts. -/

syntax (name := runExec) "run_exec" (" [" Lean.Parser.Tactic.simpLemma,* "]")?
  (Lean.Parser.Tactic.location)? : tactic

macro_rules
  | `(tactic| run_exec $[$loc]?) => `(tactic| run_exec [] $[$loc]?)
  | `(tactic| run_exec [$extra,*] $[$loc]?) => `(tactic|
      simp (disch := first | (simp only [String.reduceBEq]; done) | omega) only
        [ProofKit.exec_letVar, ProofKit.exec_assignVar, ProofKit.exec_ite,
         ProofKit.exec_panic, ProofKit.exec_nil, ProofKit.exec_returnValues,
         ProofKit.exec_requireError,
         ProofKit.andThen_continue, ProofKit.andThen_revert, ProofKit.andThen_stop,
         ProofKit.andThen_return, ProofKit.andThen_revertWithData,
         ProofKit.evalExprList_cons, ProofKit.evalExprList_nil,
         List.map_cons, List.map_nil,
         ProofKit.eval_literal, ProofKit.eval_param, ProofKit.eval_localVar,
         ProofKit.eval_add, ProofKit.eval_sub, ProofKit.eval_mul, ProofKit.eval_div,
         ProofKit.eval_eq, ProofKit.eval_lt, ProofKit.eval_gt, ProofKit.eval_le,
         ProofKit.eval_ge, ProofKit.eval_logicalNot, ProofKit.eval_calldataload,
         ProofKit.eval_calldatasize, ProofKit.eval_mload, ProofKit.eval_slt,
         ProofKit.eval_sgt, ProofKit.eval_sdiv, ProofKit.eval_shl, ProofKit.eval_sar,
         ProofKit.exec_mstore, ProofKit.exec_revertReturndata, Option.bind_some,
         ProofKit.lookup_bind_same,
         ProofKit.lookup_bind_ne, ProofKit.lookup_single, String.reduceBEq,
         ProofKit.boolWord_ne_zero, decide_eq_true_eq, ProofKit.wordNormalize_of_lt,
         ProofKit.wadd_of_lt, ProofKit.wsub_of_le, ProofKit.wmul_of_lt, ProofKit.wdiv_of_lt,
         if_pos, if_neg, ite_self, Nat.mul_div_cancel_left,
         StmtOutcome.continue.injEq, StmtOutcome.stop.injEq, exists_eq_left',
         Option.some.injEq, List.cons.injEq, and_true, $extra,*] $[$loc]?)

end ProofKit
