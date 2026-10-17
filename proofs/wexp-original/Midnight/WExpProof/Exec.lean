import Midnight.TickLibImport
import Compiler.SolidityImport.Proofs
import Midnight.WExpProof.Word

/-! Step lemmas for symbolically executing the imported `wExp` body. -/

open Compiler.CompilationModel Compiler.CompilationModel.Denote Compiler.CompilationModel.SolidityImport
open Verity.Core

namespace Midnight.TickLibImport.Exec
open Midnight.TickLibImport.Word

theorem wordNormalize_wd (n : Nat) : wordNormalize n = wd (n : Int) := by
  show n % 2 ^ 256 = _
  exact wordNat_eq_wd n

@[simp] theorem lookup_single (n : String) (v : Nat) : lookupValue [(n, v)] n = v := by
  simp [lookupValue]

theorem boolWord_ne (p : Prop) [Decidable p] :
    ((boolWord (decide p) != 0) = true) = p := by
  unfold boolWord
  by_cases h : p <;> simp [h]


variable {o : DenoteOracle} {fs : List Field} {s : DenoteState}

theorem ev_lit (n : Nat) : evalExpr o fs s (.literal n) = some (wordNormalize n) := by
  simp [evalExpr]
theorem ev_param (n : String) : evalExpr o fs s (.param n) = some (lookupValue s.bindings n) := by
  simp [evalExpr]
theorem ev_local (n : String) : evalExpr o fs s (.localVar n) = some (lookupValue s.bindings n) := by
  simp [evalExpr]
theorem ev_add {a b : Expr} {x y : Nat} (ha : evalExpr o fs s a = some x) (hb : evalExpr o fs s b = some y) :
    evalExpr o fs s (.add a b) = some ((Uint256.ofNat x + Uint256.ofNat y).val) := by
  simp [evalExpr, ha, hb]
theorem ev_sub {a b : Expr} {x y : Nat} (ha : evalExpr o fs s a = some x) (hb : evalExpr o fs s b = some y) :
    evalExpr o fs s (.sub a b) = some ((Uint256.ofNat x - Uint256.ofNat y).val) := by
  simp [evalExpr, ha, hb]
theorem ev_mul {a b : Expr} {x y : Nat} (ha : evalExpr o fs s a = some x) (hb : evalExpr o fs s b = some y) :
    evalExpr o fs s (.mul a b) = some ((Uint256.ofNat x * Uint256.ofNat y).val) := by
  simp [evalExpr, ha, hb]
theorem ev_div {a b : Expr} {x y : Nat} (ha : evalExpr o fs s a = some x) (hb : evalExpr o fs s b = some y) :
    evalExpr o fs s (.div a b) = some ((Uint256.ofNat x / Uint256.ofNat y).val) := by
  simp [evalExpr, ha, hb]
theorem ev_eq {a b : Expr} {x y : Nat} (ha : evalExpr o fs s a = some x) (hb : evalExpr o fs s b = some y) :
    evalExpr o fs s (.eq a b) = some (boolWord (decide (x = y))) := by
  simp [evalExpr, ha, hb]
theorem ev_shl {a b : Expr} {x y : Nat} (ha : evalExpr o fs s a = some x) (hb : evalExpr o fs s b = some y) :
    evalExpr o fs s (.shl a b) = some (Uint256.shl x y).val := by
  simp [evalExpr, ha, hb]
theorem ev_slt {a b : Expr} {x y : Nat} (ha : evalExpr o fs s a = some x) (hb : evalExpr o fs s b = some y) :
    evalExpr o fs s (.slt a b) = some (boolWord (decide (
        (Int256.ofUint256 (Uint256.ofNat x) : Int) < (Int256.ofUint256 (Uint256.ofNat y) : Int)))) := by
  simp [evalExpr, ha, hb]
theorem ev_sdiv {a b : Expr} {x y : Nat} (ha : evalExpr o fs s a = some x) (hb : evalExpr o fs s b = some y) :
    evalExpr o fs s (.sdiv a b) = some (Int256.div (Int256.ofUint256 (Uint256.ofNat x))
        (Int256.ofUint256 (Uint256.ofNat y))).toUint256.val := by
  simp [evalExpr, ha, hb]


theorem st_let (n : String) (e : Expr) (rest : List Stmt) :
    execStmtList o fs s (.letVar n e :: rest) =
      match evalExpr o fs s e with
      | some v => execStmtList o fs {s with bindings := bindValue s.bindings n v} rest
      | none => .revert := by
  simp only [execStmtList, execStmt]; cases evalExpr o fs s e <;> rfl
theorem st_assign (n : String) (e : Expr) (rest : List Stmt) :
    execStmtList o fs s (.assignVar n e :: rest) =
      match evalExpr o fs s e with
      | some v => execStmtList o fs {s with bindings := bindValue s.bindings n v} rest
      | none => .revert := by
  simp only [execStmtList, execStmt]; cases evalExpr o fs s e <;> rfl
theorem st_ite (c : Expr) (yes no rest : List Stmt) :
    execStmtList o fs s (.ite c yes no :: rest) =
      match evalExpr o fs s c with
      | some v => if v != 0 then execStmtList o fs s (yes ++ rest) else execStmtList o fs s (no ++ rest)
      | none => .revert := by
  rw [show execStmtList o fs s (.ite c yes no :: rest) = execStmtList o fs s ([.ite c yes no] ++ rest) from rfl,
    exec_append]
  simp only [exec_singleton, execStmt]
  cases evalExpr o fs s c with
  | none => rfl
  | some v =>
    by_cases h : (v != 0) = true
    · simp only [h, if_true, exec_append]
    · simp only [Bool.not_eq_true] at h; simp only [h, exec_append]; rfl
theorem st_revertRd (rest : List Stmt) :
    execStmtList o fs s (.revertReturndata :: rest) = .revertWithData (s.world.returndata.flatMap wordBytes) := by
  simp only [execStmtList, execStmt]
theorem st_panic (c : PanicCode) (rest : List Stmt) :
    execStmtList o fs s (.panic c :: rest) = .revertWithData (panicBytes c.toNat) := by
  simp only [execStmtList, execStmt]
theorem st_return (e : Expr) :
    execStmtList o fs s [.returnValues [e]] =
      match evalExpr o fs s e with
      | some v => .stop { s with observedReturnWords := some [wordNormalize v], observedStop := false }
      | none => .revert := by
  simp only [execStmtList, execStmt, evalExprList]
  cases evalExpr o fs s e <;> rfl

end Midnight.TickLibImport.Exec
