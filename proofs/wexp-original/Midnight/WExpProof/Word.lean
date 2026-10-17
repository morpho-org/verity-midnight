import Mathlib.Tactic
import Verity.Core.Int256

/-! Int-level view of 256-bit word arithmetic. -/

open Verity.Core

namespace Midnight.TickLibImport.Word

/-- The word representing an integer. -/
def wd (a : Int) : Nat := (a % (2 ^ 256 : Int)).toNat

/-- Signed reading of the word representing `a`. -/
def sx (a : Int) : Int :=
  if a % (2 ^ 256 : Int) < 2 ^ 255 then a % (2 ^ 256 : Int) else a % (2 ^ 256 : Int) - 2 ^ 256

theorem wd_lt (a : Int) : wd a < 2 ^ 256 := by
  unfold wd
  have h1 : 0 ≤ a % (2 ^ 256 : Int) := Int.emod_nonneg _ (by norm_num)
  have h2 : a % (2 ^ 256 : Int) < 2 ^ 256 := Int.emod_lt_of_pos _ (by norm_num)
  omega

theorem wd_cast (a : Int) : ((wd a : Nat) : Int) = a % (2 ^ 256 : Int) := by
  unfold wd
  have h1 : 0 ≤ a % (2 ^ 256 : Int) := Int.emod_nonneg _ (by norm_num)
  omega

theorem wd_eq_iff (a b : Int) : wd a = wd b ↔ a % (2 ^ 256 : Int) = b % (2 ^ 256 : Int) := by
  constructor
  · intro h; rw [← wd_cast, ← wd_cast, h]
  · intro h; unfold wd; rw [h]

theorem wd_emod (a : Int) : wd (a % (2 ^ 256 : Int)) = wd a := by
  rw [wd_eq_iff, Int.emod_emod_of_dvd _ (dvd_refl _)]

theorem wd_cast_wd (a : Int) : wd ((wd a : Nat) : Int) = wd a := by
  rw [wd_cast, wd_emod]

@[simp] theorem ofNat_wd_val (a : Int) : (Uint256.ofNat (wd a)).val = wd a := by
  show wd a % Uint256.modulus = wd a
  exact Nat.mod_eq_of_lt (wd_lt a)

theorem ofNat_val_mod (n : Nat) : (Uint256.ofNat n).val = n % 2 ^ 256 := rfl

theorem wd_natCast (n : Nat) : wd (n : Int) = n % 2 ^ 256 := by
  unfold wd; omega

theorem wordNat_eq_wd (n : Nat) : n % 2 ^ 256 = wd (n : Int) := (wd_natCast n).symm

theorem add_wd (a b : Int) : (Uint256.ofNat (wd a) + Uint256.ofNat (wd b)).val = wd (a + b) := by
  show (wd a % 2^256 + wd b % 2^256) % 2^256 = wd (a + b)
  rw [Nat.mod_eq_of_lt (wd_lt a), Nat.mod_eq_of_lt (wd_lt b), wordNat_eq_wd]
  rw [wd_eq_iff]; push_cast; rw [wd_cast, wd_cast]
  norm_num

theorem mul_wd (a b : Int) : (Uint256.ofNat (wd a) * Uint256.ofNat (wd b)).val = wd (a * b) := by
  show (wd a % 2^256 * (wd b % 2^256)) % 2^256 = wd (a * b)
  rw [Nat.mod_eq_of_lt (wd_lt a), Nat.mod_eq_of_lt (wd_lt b), wordNat_eq_wd]
  rw [wd_eq_iff]; push_cast; rw [wd_cast, wd_cast]
  rw [Int.mul_emod a b]; norm_num

theorem sub_wd (a b : Int) : (Uint256.ofNat (wd a) - Uint256.ofNat (wd b)).val = wd (a - b) := by
  show (Uint256.sub _ _).val = _
  unfold Uint256.sub
  simp only [ofNat_wd_val]
  have ha := wd_lt a; have hb := wd_lt b
  have hca := wd_cast a; have hcb := wd_cast b
  split_ifs with h
  · rw [ofNat_val_mod, wordNat_eq_wd, wd_eq_iff]
    push_cast [h]
    rw [hca, hcb]; norm_num
  · rw [ofNat_val_mod, wordNat_eq_wd, wd_eq_iff]
    have hm : Uint256.modulus = 2 ^ 256 := rfl
    rw [hm]
    have h' : wd a < wd b := by omega
    push_cast [h'.le, show wd b - wd a ≤ 2 ^ 256 by omega]
    have hca' : ((wd a : Nat) : Int) = a % 115792089237316195423570985008687907853269984665640564039457584007913129639936 := by rw [hca]; norm_num
    have hcb' : ((wd b : Nat) : Int) = b % 115792089237316195423570985008687907853269984665640564039457584007913129639936 := by rw [hcb]; norm_num
    omega

theorem toInt_wd (a : Int) : (Int256.ofUint256 (Uint256.ofNat (wd a))).toInt = sx a := by
  unfold Int256.toInt Int256.ofUint256 sx
  simp only [ofNat_wd_val]
  have hc := wd_cast a
  simp only [Int256.signBit, Int256.modulus, Uint256.modulus, UINT256_MODULUS] at *
  norm_num at *
  split_ifs <;> omega

theorem sx_of_range {a : Int} (h1 : -2 ^ 255 ≤ a) (h2 : a < 2 ^ 255) : sx a = a := by
  unfold sx
  norm_num at *
  split_ifs <;> omega

theorem wd_sx (a : Int) : wd (sx a) = wd a := by
  unfold sx; rw [wd_eq_iff]; norm_num; split_ifs <;> omega

theorem sx_range (a : Int) : -2 ^ 255 ≤ sx a ∧ sx a < 2 ^ 255 := by
  unfold sx; norm_num; split_ifs <;> omega

theorem ofInt_val (q : Int) : (Int256.ofInt q).toUint256.val = wd q := by
  unfold Int256.ofInt
  split_ifs with h
  · simp only [Int256.toUint256, Int256.ofUint256, ofNat_val_mod, Int256.modulus, Uint256.modulus, UINT256_MODULUS]
    rw [wordNat_eq_wd, wd_eq_iff]
    have hlt : q.natAbs % 2 ^ 256 ≤ 2 ^ 256 := (Nat.mod_lt _ (by norm_num)).le
    push_cast [hlt]
    omega
  · simp only [Int256.toUint256, Int256.ofUint256, ofNat_val_mod]
    rw [wordNat_eq_wd]; congr 1; omega

/-- Signed truncating division, as `Int256.div` computes it. -/
def sdivI (x y : Int) : Int :=
  if y = 0 then 0 else
    if (x < 0) = (y < 0) then ((x.natAbs / y.natAbs : Nat) : Int) else -((x.natAbs / y.natAbs : Nat) : Int)

theorem sdiv_wd (a b : Int) :
    (Int256.div (Int256.ofUint256 (Uint256.ofNat (wd a))) (Int256.ofUint256 (Uint256.ofNat (wd b)))).toUint256.val
      = wd (sdivI (sx a) (sx b)) := by
  unfold Int256.div sdivI
  simp only [toInt_wd, Int256.signedAbsNat]
  by_cases hb : sx b = 0
  · simp only [hb, if_true]; rfl
  · by_cases ha' : sx a < 0 <;> by_cases hb' : sx b < 0 <;> simp [hb, ha', hb', ofInt_val]

theorem shl_wd (q e : Int) :
    ((Uint256.ofNat (wd q)).shl (Uint256.ofNat (wd e))).val = wd ((wd e : Int) * 2 ^ (wd q)) := by
  unfold Uint256.shl
  simp only [ofNat_val_mod, Nat.shiftLeft_eq, Nat.mod_eq_of_lt (wd_lt q), Nat.mod_eq_of_lt (wd_lt e)]
  rw [wordNat_eq_wd]; push_cast; rfl

theorem div_wd (a b : Int) :
    (Uint256.ofNat (wd a) / Uint256.ofNat (wd b)).val = wd ((wd a : Int) / (wd b : Int)) := by
  show (Uint256.div _ _).val = _
  unfold Uint256.div
  simp only [ofNat_wd_val]
  split_ifs with h
  · rw [h]; simp [wd]
  · rw [ofNat_val_mod, wordNat_eq_wd]; push_cast; rfl

theorem word_toInt (x : Int256) : x.word.val = wd x.toInt := by
  unfold Int256.toInt
  have h := x.word.isLt
  simp only [UINT256_MODULUS] at h
  simp only [Int256.signBit, Int256.modulus, Uint256.modulus, UINT256_MODULUS]
  split_ifs with h1
  · unfold wd; norm_num at *; omega
  · unfold wd; norm_num at *; omega

theorem sx_natCast {n : Nat} (h : n < 2 ^ 255) : sx (n : Int) = n :=
  sx_of_range (by omega) (by exact_mod_cast h)

@[simp] theorem sx_zero : sx 0 = 0 := sx_of_range (by norm_num) (by norm_num)

@[simp] theorem sx_ofNat (n : Nat) [n.AtLeastTwo] (h : n < 2 ^ 255) :
    sx (OfNat.ofNat n : Int) = OfNat.ofNat n :=
  sx_natCast h

theorem sdivI_nonneg {a b : Int} (ha : 0 ≤ a) (hb : 0 < b) : sdivI a b = a / b := by
  unfold sdivI
  rw [if_neg (by omega), if_pos (by simp; omega)]
  have h1 : ((a.natAbs : Nat) : Int) = a := Int.natAbs_of_nonneg ha
  have h2 : ((b.natAbs : Nat) : Int) = b := Int.natAbs_of_nonneg hb.le
  rw [Int.natCast_div, h1, h2]

theorem sdivI_neg {a b : Int} (ha : a < 0) (hb : 0 < b) : sdivI a b = -((-a) / b) := by
  unfold sdivI
  rw [if_neg (by omega), if_neg (by simp; omega)]
  have h1 : ((a.natAbs : Nat) : Int) = -a := by omega
  have h2 : ((b.natAbs : Nat) : Int) = b := Int.natAbs_of_nonneg hb.le
  rw [Int.natCast_div, h1, h2]

end Midnight.TickLibImport.Word
