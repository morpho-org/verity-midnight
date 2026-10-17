import Midnight.WExpProof.Word

/-! The integer function computed by the imported `wExp`, and its monotonicity. -/

set_option linter.unusedSectionVars false

namespace Midnight.TickLibImport.Math
open Midnight.TickLibImport.Word

def qOf (y : Int) : Int := sdivI (y + 322611214989459870) 693147180559945309
def rOf (y : Int) : Int := y - qOf y * 693147180559945309
def sOf (y : Int) : Int := sdivI (rOf y * rOf y) 2000000000000000000
def tOf (y : Int) : Int := sdivI (sOf y * rOf y) 3000000000000000000
def eOf (y : Int) : Int := 1000000000000000000 + rOf y + sOf y + tOf y
def posW (y : Int) : Int := eOf y * 2 ^ (qOf y).toNat

/-- Largest input magnitude. -/
def M : Int := 16817989975223754156

theorem q_eq {y : Int} (hy : 0 ≤ y) : qOf y = (y + 322611214989459870) / 693147180559945309 :=
  sdivI_nonneg (by omega) (by norm_num)

theorem q_bounds {y : Int} (hy0 : 0 ≤ y) (hy : y ≤ M) : 0 ≤ qOf y ∧ qOf y ≤ 24 := by
  rw [q_eq hy0]; unfold M at hy; omega

theorem r_bounds {y : Int} (hy0 : 0 ≤ y) :
    -322611214989459870 ≤ rOf y ∧ rOf y ≤ 370535965570485438 := by
  unfold rOf; rw [q_eq hy0]; omega

/-- The polynomial part, as a function of the residual. -/
def sR (r : Int) : Int := sdivI (r * r) 2000000000000000000
def tR (r : Int) : Int := sdivI (sR r * r) 3000000000000000000
def eR (r : Int) : Int := 1000000000000000000 + r + sR r + tR r

theorem eOf_eq (y : Int) : eOf y = eR (rOf y) := rfl

theorem sR_eq (r : Int) : sR r = r * r / 2000000000000000000 :=
  sdivI_nonneg (mul_self_nonneg r) (by norm_num)

theorem tR_pos {r : Int} (hr : 0 ≤ r) : tR r = sR r * r / 3000000000000000000 := by
  have : 0 ≤ sR r := by rw [sR_eq]; exact Int.ediv_nonneg (mul_self_nonneg r) (by norm_num)
  exact sdivI_nonneg (mul_nonneg this hr) (by norm_num)

theorem tR_neg {r : Int} (hr : r < 0) : tR r = -((sR r * (-r)) / 3000000000000000000) := by
  have h0 : 0 ≤ sR r := by rw [sR_eq]; exact Int.ediv_nonneg (mul_self_nonneg r) (by norm_num)
  unfold tR
  rcases h0.lt_or_eq with h | h
  · rw [sdivI_neg (by nlinarith) (by norm_num)]; ring_nf
  · rw [← h]; simp [sdivI]

theorem sR_nonneg (r : Int) : 0 ≤ sR r := by
  rw [sR_eq]; exact Int.ediv_nonneg (mul_self_nonneg r) (by norm_num)

theorem sR_mul_le (r : Int) : sR r * 2000000000000000000 ≤ r * r := by
  rw [sR_eq]; exact Int.ediv_mul_le _ (by norm_num)

theorem sR_lt (r : Int) : r * r < (sR r + 1) * 2000000000000000000 := by
  rw [sR_eq]; have := Int.lt_ediv_add_one_mul_self (r * r) (show (0 : Int) < 2000000000000000000 by norm_num)
  linarith

theorem sR_mono {a b : Int} (h : a * a ≤ b * b) : sR a ≤ sR b := by
  rw [sR_eq, sR_eq]; exact Int.ediv_le_ediv (by norm_num) h

theorem eR_mono {r1 r2 : Int} (h1 : -322611214989459870 ≤ r1) (h12 : r1 ≤ r2)
    (h2 : r2 ≤ 370535965570485438) : eR r1 ≤ eR r2 := by
  unfold eR
  rcases le_or_gt 0 r1 with p1 | n1
  · have hs : sR r1 ≤ sR r2 := sR_mono (by nlinarith)
    have hs0 := sR_nonneg r1
    rw [tR_pos p1, tR_pos (by omega)]
    have : sR r1 * r1 / 3000000000000000000 ≤ sR r2 * r2 / 3000000000000000000 :=
      Int.ediv_le_ediv (by norm_num) (by nlinarith)
    omega
  rcases le_or_gt 0 r2 with p2 | n2
  · rw [tR_neg n1, tR_pos p2]
    have hs1 := sR_mul_le r1
    have hs0 := sR_nonneg r1
    have hlt : sR r1 ≤ -r1 := by nlinarith
    have : 0 ≤ sR r1 * -r1 / 3000000000000000000 := Int.ediv_nonneg (by nlinarith) (by norm_num)
    have : 0 ≤ sR r2 * r2 / 3000000000000000000 := Int.ediv_nonneg (mul_nonneg (sR_nonneg r2) p2) (by norm_num)
    have := sR_nonneg r2
    omega
  · rw [tR_neg n1, tR_neg n2]
    have hs1 := sR_mul_le r1
    have hs2 := sR_lt r2
    have hsm : sR r2 ≤ sR r1 := sR_mono (by nlinarith)
    have hd : sR r1 - sR r2 ≤ r2 - r1 := by
      by_contra hc
      push Not at hc
      nlinarith
    have : sR r2 * -r2 / 3000000000000000000 ≤ sR r1 * -r1 / 3000000000000000000 :=
      Int.ediv_le_ediv (by norm_num) (by nlinarith [sR_nonneg r2])
    omega

theorem eR_top : eR 370535965570485438 = 1447663323139670138 := by
  rw [eR, tR_pos (by norm_num), sR_eq]; norm_num

theorem eR_bot : eR (-322611214989459870) = 723831661569835069 := by
  rw [eR, tR_neg (by norm_num), sR_eq]; norm_num

theorem posW_eq (y : Int) : posW y = eR (rOf y) * 2 ^ (qOf y).toNat := rfl

theorem posW_mono {y1 y2 : Int} (h0 : 0 ≤ y1) (h12 : y1 ≤ y2) (h2 : y2 ≤ M) :
    posW y1 ≤ posW y2 := by
  have hq1 := q_bounds h0 (by omega)
  have hq2 := q_bounds (by omega : 0 ≤ y2) h2
  have hr1 := r_bounds h0
  have hr2 := r_bounds (by omega : 0 ≤ y2)
  have hqm : qOf y1 ≤ qOf y2 := by
    rw [q_eq h0, q_eq (by omega)]; exact Int.ediv_le_ediv (by norm_num) (by omega)
  rw [posW_eq, posW_eq]
  rcases hqm.lt_or_eq with hlt | heq
  · have e1 : eR (rOf y1) ≤ eR 370535965570485438 := eR_mono hr1.1 hr1.2 (le_refl _)
    have e2 : eR (-322611214989459870) ≤ eR (rOf y2) := eR_mono (le_refl _) hr2.1 hr2.2
    rw [eR_top] at e1; rw [eR_bot] at e2
    have hn : (qOf y1).toNat + 1 ≤ (qOf y2).toNat := by omega
    have hp : (2 : Int) ^ ((qOf y1).toNat + 1) ≤ 2 ^ (qOf y2).toNat :=
      pow_le_pow_right₀ (by norm_num) hn
    have hpos : (0 : Int) < 2 ^ (qOf y1).toNat := by positivity
    rw [pow_succ] at hp
    calc eR (rOf y1) * 2 ^ (qOf y1).toNat ≤ 1447663323139670138 * 2 ^ (qOf y1).toNat :=
          mul_le_mul_of_nonneg_right e1 hpos.le
      _ = 723831661569835069 * (2 ^ (qOf y1).toNat * 2) := by ring
      _ ≤ 723831661569835069 * 2 ^ (qOf y2).toNat := mul_le_mul_of_nonneg_left hp (by norm_num)
      _ ≤ eR (rOf y2) * 2 ^ (qOf y2).toNat := mul_le_mul_of_nonneg_right e2 (by positivity)
  · rw [heq]
    apply mul_le_mul_of_nonneg_right _ (by positivity)
    apply eR_mono hr1.1 _ hr2.2
    unfold rOf; rw [heq]; omega

theorem eR_bounds {y : Int} (hy0 : 0 ≤ y) :
    723831661569835069 ≤ eR (rOf y) ∧ eR (rOf y) ≤ 1447663323139670138 := by
  have hr := r_bounds hy0
  constructor
  · rw [← eR_bot]; exact eR_mono (le_refl _) hr.1 hr.2
  · rw [← eR_top]; exact eR_mono hr.1 hr.2 (le_refl _)

theorem posW_bounds {y : Int} (hy0 : 0 ≤ y) (hy : y ≤ M) :
    0 < posW y ∧ posW y ≤ 1447663323139670138 * 2 ^ 24 := by
  have he := eR_bounds hy0
  have hq := q_bounds hy0 hy
  have hp : (2 : Int) ^ (qOf y).toNat ≤ 2 ^ 24 := pow_le_pow_right₀ (by norm_num) (by omega)
  have hp0 : (0 : Int) < 2 ^ (qOf y).toNat := by positivity
  rw [posW_eq]
  constructor
  · nlinarith
  · calc eR (rOf y) * 2 ^ (qOf y).toNat ≤ 1447663323139670138 * 2 ^ (qOf y).toNat :=
          mul_le_mul_of_nonneg_right he.2 hp0.le
      _ ≤ 1447663323139670138 * 2 ^ 24 := mul_le_mul_of_nonneg_left hp (by norm_num)

theorem posW_zero : posW 0 = 1000000000000000000 := by
  have hq : qOf 0 = 0 := by rw [q_eq (le_refl _)]; norm_num
  rw [posW_eq, show rOf 0 = 0 by unfold rOf; rw [hq]; norm_num, hq]
  rw [eR, tR_pos (le_refl _), sR_eq]; norm_num

theorem div_anti (a b c : Int) (ha : 0 ≤ a) (hb : 0 < b) (hbc : b ≤ c) : a / c ≤ a / b := by
  rw [Int.le_ediv_iff_mul_le hb]
  have h0 : 0 ≤ a / c := Int.ediv_nonneg ha (by omega)
  have h1 : a / c * c ≤ a := Int.ediv_mul_le a (by omega)
  nlinarith

/-- The integer value returned by the imported `wExp` on the input range. -/
def wexpI (x : Int) : Int :=
  if x < 0 then 1000000000000000000000000000000000000 / posW (-x) else posW x

theorem wexpI_mono {x y : Int} (hy : -M ≤ y) (hyx : y < x) (hx : x ≤ M) : wexpI y ≤ wexpI x := by
  unfold wexpI
  rcases le_or_gt 0 y with p | n
  · rw [if_neg (by omega), if_neg (by omega)]; exact posW_mono p hyx.le hx
  rw [if_pos n]
  have hb := posW_bounds (by omega : 0 ≤ -y) (by omega)
  rcases le_or_gt 0 x with px | nx
  · rw [if_neg (by omega)]
    have h1 : posW 0 ≤ posW (-y) := posW_mono (le_refl _) (by omega) (by omega)
    have h2 : posW 0 ≤ posW x := posW_mono (le_refl _) px hx
    rw [posW_zero] at h1 h2
    have := div_anti 1000000000000000000000000000000000000 _ _ (by norm_num) (by norm_num) h1
    norm_num at this
    omega
  · rw [if_pos nx]
    have hbx := posW_bounds (by omega : 0 ≤ -x) (by omega)
    exact div_anti _ _ _ (by norm_num) hbx.1 (posW_mono (by omega) (by omega) (by omega))

theorem wexpI_bounds {x : Int} (hx0 : -M ≤ x) (hx : x ≤ M) :
    0 ≤ wexpI x ∧ wexpI x < 2 ^ 255 := by
  unfold wexpI
  split_ifs with h
  · have hb := posW_bounds (by omega : 0 ≤ -x) (by omega)
    have h1 : posW 0 ≤ posW (-x) := posW_mono (le_refl _) (by omega) (by omega)
    rw [posW_zero] at h1
    have := div_anti 1000000000000000000000000000000000000 _ _ (by norm_num) (by norm_num) h1
    have := Int.ediv_nonneg (show (0:Int) ≤ 1000000000000000000000000000000000000 by norm_num) hb.1.le
    norm_num at *
    omega
  · have hb := posW_bounds (by omega : 0 ≤ x) hx
    constructor <;> omega

/-! ## Facts used to read the model's word arithmetic -/

theorem fold_q (y : Int) : sdivI (y + 322611214989459870) 693147180559945309 = qOf y := rfl
theorem fold_r (y : Int) : y - qOf y * 693147180559945309 = rOf y := rfl
theorem fold_s (y : Int) : sdivI (rOf y * rOf y) 2000000000000000000 = sOf y := rfl
theorem fold_t (y : Int) : sdivI (sOf y * rOf y) 3000000000000000000 = tOf y := rfl
theorem fold_e (y : Int) : 1000000000000000000 + rOf y + sOf y + tOf y = eOf y := rfl
theorem fold_p (y : Int) : eOf y * 2 ^ (qOf y).toNat = posW y := rfl

theorem sx_ln2 : sx 693147180559945309 = 693147180559945309 := sx_of_range (by norm_num) (by norm_num)
theorem sx_2w : sx 2000000000000000000 = 2000000000000000000 := sx_of_range (by norm_num) (by norm_num)
theorem sx_3w : sx 3000000000000000000 = 3000000000000000000 := sx_of_range (by norm_num) (by norm_num)

section
variable {y : Int} (hy0 : 0 ≤ y) (hy : y ≤ M)
include hy0 hy

theorem core_sx1 : sx (y + 322611214989459870) = y + 322611214989459870 := by
  unfold M at hy; exact sx_of_range (by omega) (by omega)

theorem core_sx2 : sx (rOf y * rOf y) = rOf y * rOf y := by
  have hr := r_bounds hy0
  exact sx_of_range (by nlinarith) (by nlinarith)

theorem s_bounds : 0 ≤ sOf y ∧ sOf y ≤ 68648456000000000 := by
  have hr := r_bounds hy0
  have h := sR_mul_le (rOf y)
  have h0 := sR_nonneg (rOf y)
  change 0 ≤ sR (rOf y) ∧ sR (rOf y) ≤ _
  constructor
  · exact h0
  · nlinarith

theorem core_sx3 : sx (sOf y * rOf y) = sOf y * rOf y := by
  have hr := r_bounds hy0
  have hs := s_bounds hy0 hy
  exact sx_of_range (by nlinarith) (by nlinarith)

theorem core_e : ((wd (eOf y) : Nat) : Int) = eOf y := by
  have he := eR_bounds hy0
  rw [wd_cast, eOf_eq]
  exact Int.emod_eq_of_lt (by omega) (by norm_num; omega)

theorem core_q : wd (qOf y) = (qOf y).toNat := by
  have hq := q_bounds hy0 hy
  unfold wd; rw [Int.emod_eq_of_lt (by omega) (by norm_num; omega)]

theorem core_p : ((wd (posW y) : Nat) : Int) = posW y := by
  have hb := posW_bounds hy0 hy
  rw [wd_cast]; exact Int.emod_eq_of_lt (by omega) (by norm_num at hb ⊢; omega)

theorem core_p_ne : ¬ posW y % 115792089237316195423570985008687907853269984665640564039457584007913129639936 = 0 := by
  have hb := posW_bounds hy0 hy
  rw [Int.emod_eq_of_lt (by omega) (by norm_num at hb ⊢; omega)]; omega

end

end Midnight.TickLibImport.Math
