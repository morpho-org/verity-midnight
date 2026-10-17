import Midnight.TickLibImportSpec
import Midnight.WExpProof.Model

namespace Midnight.TickLibImport

open Verity.Core Midnight.TickLibImport.Word Midnight.TickLibImport.Math

private theorem range_bounds {x : Int256} (hx : Spec.TickLibImport.inRange x) :
    -M ≤ x.toInt ∧ x.toInt ≤ M := by
  unfold Spec.TickLibImport.inRange Spec.TickLibImport.maxInput
    at hx
  unfold M; norm_num at hx; omega

private theorem wd_of_bounds {z : Int} (h0 : 0 ≤ z) (h1 : z < 2 ^ 255) : ((wd z : Nat) : Int) = z := by
  rw [wd_cast]; exact Int.emod_eq_of_lt h0 (by omega)

theorem wExpIsMonotonic : Spec.TickLibImport.wExpIsMonotonic := by
  intro o w x y expX expY hx hy hxy hX hY
  rw [Model.wExp_eq o w x hx] at hX
  rw [Model.wExp_eq o w y hy] at hY
  cases hX; cases hY
  have bx := range_bounds hx
  have b_y := range_bounds hy
  have hlt : y.toInt < x.toInt := hxy
  have hm := wexpI_mono b_y.1 hlt bx.2
  have ex := wexpI_bounds bx.1 bx.2
  have ey := wexpI_bounds b_y.1 b_y.2
  show (Uint256.ofNat (wd (wexpI y.toInt))).val ≤ (Uint256.ofNat (wd (wexpI x.toInt))).val
  rw [ofNat_wd_val, ofNat_wd_val]
  have h1 := wd_of_bounds ex.1 ex.2
  have h2 := wd_of_bounds ey.1 ey.2
  omega

theorem wExpSucceeds : Spec.TickLibImport.wExpSucceeds := by
  intro o w x hx
  exact ⟨_, Model.wExp_eq o w x hx⟩

end Midnight.TickLibImport
