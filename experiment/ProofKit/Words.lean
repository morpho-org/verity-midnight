import Compiler.SolidityImport.Access

/-!
# 256-bit word operations as plain `Nat` functions

`evalExpr` computes checked Solidity arithmetic through `Uint256`, which wraps.
The `ProofKit.Exec` evaluation lemmas restate those arms with `wadd`/`wsub`/
`wmul`/`wdiv`, and the `*_of_lt`/`*_of_le` lemmas below remove the wrapping
once a bound is known. This keeps symbolic terms in plain `Nat` arithmetic,
where `omega` and `Nat` simprocs apply.
-/

open Compiler.CompilationModel.Denote
open Verity.Core

namespace ProofKit

/-- Wrapping 256-bit addition, as computed by `Expr.add`. -/
def wadd (x y : Nat) : Nat := (Uint256.ofNat x + Uint256.ofNat y).val
/-- Wrapping 256-bit subtraction, as computed by `Expr.sub`. -/
def wsub (x y : Nat) : Nat := (Uint256.ofNat x - Uint256.ofNat y).val
/-- Wrapping 256-bit multiplication, as computed by `Expr.mul`. -/
def wmul (x y : Nat) : Nat := (Uint256.ofNat x * Uint256.ofNat y).val
/-- 256-bit division (`x / 0 = 0`), as computed by `Expr.div`. -/
def wdiv (x y : Nat) : Nat := (Uint256.ofNat x / Uint256.ofNat y).val

theorem wordNormalize_of_lt (n : Nat) (h : n < 2 ^ 256) : wordNormalize n = n :=
  Nat.mod_eq_of_lt h

theorem wadd_of_lt (x y : Nat) (h : x + y < 2 ^ 256) : wadd x y = x + y := by
  have hx : x < 2 ^ 256 := by omega
  have hy : y < 2 ^ 256 := by omega
  show ((x % 2 ^ 256 + y % 2 ^ 256) % 2 ^ 256) = x + y
  rw [Nat.mod_eq_of_lt hx, Nat.mod_eq_of_lt hy, Nat.mod_eq_of_lt h]

theorem wmul_of_lt (x y : Nat) (h : x * y < 2 ^ 256) (hx : x < 2 ^ 256) (hy : y < 2 ^ 256) :
    wmul x y = x * y := by
  show ((x % 2 ^ 256 * (y % 2 ^ 256)) % 2 ^ 256) = x * y
  rw [Nat.mod_eq_of_lt hx, Nat.mod_eq_of_lt hy, Nat.mod_eq_of_lt h]

theorem wsub_of_le (x y : Nat) (h : y ≤ x) (hx : x < 2 ^ 256) : wsub x y = x - y := by
  have hy : y < 2 ^ 256 := by omega
  show (Uint256.sub (Uint256.ofNat x) (Uint256.ofNat y)).val = x - y
  unfold Uint256.sub
  simp only [Uint256.val_ofNat, Uint256.modulus, UINT256_MODULUS,
    Nat.mod_eq_of_lt hx, Nat.mod_eq_of_lt hy, h, if_true]
  exact Nat.mod_eq_of_lt (by omega)

theorem wdiv_of_lt (x y : Nat) (hx : x < 2 ^ 256) (hy : y < 2 ^ 256) :
    wdiv x y = x / y := by
  show (Uint256.div (Uint256.ofNat x) (Uint256.ofNat y)).val = x / y
  unfold Uint256.div
  simp only [Uint256.val_ofNat, Uint256.modulus, UINT256_MODULUS,
    Nat.mod_eq_of_lt hx, Nat.mod_eq_of_lt hy]
  split
  · subst_vars; simp
  · exact Nat.mod_eq_of_lt (Nat.lt_of_le_of_lt (Nat.div_le_self _ _) hx)

theorem boolWord_ne_zero (b : Bool) : (boolWord b != 0) = b := by
  cases b <;> rfl

end ProofKit
