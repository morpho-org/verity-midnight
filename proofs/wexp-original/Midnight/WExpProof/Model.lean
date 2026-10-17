import Midnight.WExpProof.Exec
import Midnight.WExpProof.Math
import Midnight.TickLibImportSpec

/-! The imported `wExp` computes `wexpI` on the input range. -/

open Compiler.CompilationModel Compiler.CompilationModel.Denote Compiler.CompilationModel.SolidityImport
open Verity.Core Midnight.TickLibImport.Exec Midnight.TickLibImport.Word Midnight.TickLibImport.Math

set_option linter.unusedSimpArgs false

namespace Midnight.TickLibImport.Model

theorem wd_e36 : ((wd 1000000000000000000000000000000000000 : Nat) : Int) = 1000000000000000000000000000000000000 := by
  rw [wd_cast]; norm_num

set_option maxHeartbeats 4000000 in
theorem wExp_eq (o : DenoteOracle) (w : Verity.ContractState) (x : Int256)
    (hx : Spec.TickLibImport.inRange x) :
    tickLib.wExp o w x = some (Uint256.ofNat (wd (wexpI x.toInt))) := by
  have hb : -M ≤ x.toInt ∧ x.toInt ≤ M := by
    unfold Spec.TickLibImport.inRange Spec.TickLibImport.maxInput
      at hx
    unfold M; norm_num at hx; omega
  have hsx : sx x.toInt = x.toInt := sx_of_range (by unfold M at hb; omega) (by unfold M at hb; omega)
  unfold tickLib.wExp runFunction
  simp (config := {decide := true}) only [functionBody, functionBody.go, tickLib.model, ↓reduceIte]
  simp only [Word.toWord, Int256.toUint256, word_toInt]
  simp only [st_let, st_ite, st_assign, st_revertRd, st_panic, st_return, evalExpr, Option.bind_eq_bind,
    Option.pure_def, Option.bind_some, lookup_bind_same, ne_eq, lookup_bind_other, String.reduceEq,
    not_false_eq_true, List.cons_append, List.nil_append, wordNormalize_wd, add_wd, sub_wd, mul_wd, sdiv_wd,
    toInt_wd, shl_wd, div_wd, boolWord_ne, wd_eq_iff, Nat.cast_ofNat, Nat.cast_zero, lookup_single,
    Int.reduceMod, Int.reducePow, decide_false, decide_true, if_false, if_true, sx_zero, Nat.reducePow,
    sx_ln2, sx_2w, sx_3w, hsx]
  unfold wexpI
  by_cases hn : x.toInt < 0
  · have hy0 : 0 ≤ 0 - x.toInt := by omega
    have hy : 0 - x.toInt ≤ M := by omega
    have hsy : sx (0 - x.toInt) = 0 - x.toInt := sx_of_range (by unfold M at hb; omega) (by unfold M at hb; omega)
    simp only [hn, if_true, hsy, show ¬ (0 - x.toInt < 0) by omega, if_false]
    rw [show -x.toInt = 0 - x.toInt by ring]
    generalize 0 - x.toInt = y at hy0 hy ⊢
    simp only [core_sx1 hy0 hy, fold_q, fold_r, core_sx2 hy0 hy, fold_s, core_sx3 hy0 hy, fold_t, fold_e,
      core_e hy0 hy, core_q hy0 hy, fold_p, core_p_ne hy0 hy, if_false, Int.reduceEq, core_p hy0 hy,
      wd_e36, wd_cast_wd, Word.ofWord]
  · simp only [hn, if_false]
    have hy0 : 0 ≤ x.toInt := by omega
    have hy : x.toInt ≤ M := hb.2
    generalize x.toInt = y at hy0 hy ⊢
    simp only [core_sx1 hy0 hy, fold_q, fold_r, core_sx2 hy0 hy, fold_s, core_sx3 hy0 hy, fold_t, fold_e,
      core_e hy0 hy, core_q hy0 hy, fold_p, Int.reduceEq, if_false, wd_cast_wd, Word.ofWord]

end Midnight.TickLibImport.Model
