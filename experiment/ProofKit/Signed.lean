import ProofKit.Exec

/-!
# Signed words as `Int`

`ofI a` is the two's-complement word of `a : Int` (`a` modulo `2^256`). The word
operations of the `Denote` interpreter commute with it, so a symbolic run of
signed (`int256`) code can be stated, and reasoned about, in `Int`:

* `wadd_ofI`, `wsub_ofI`, `wmul_ofI`: wrapping arithmetic is `Int` arithmetic
  modulo `2^256`.
* `toInt_ofI`, `word_eq_ofI`, `ofInt_val`: moving between `ofI`, `Int256`
  values and their words.
* `sdiv_ofI`: signed division of in-range words is `Int.tdiv` (rounds toward
  zero).
* `shl_ofI`: a left shift of a small value is multiplication by a power of two.
* `wordNormalize_eq`: literals (`eval_literal`) as `ofI`.
* `ofI_le_ofI`, `ofI_ne_lit`, `wdiv_ofI`: unsigned comparisons, literal
  tests and unsigned division on nonnegative in-range values.
* `tdiv_cases`: `Int.tdiv` by a positive divisor as `Int` division.
* `run_sexec`: `run_exec` for signed code, where every word is `ofI a`.

Comparisons (`eval_slt`, `eval_sgt`) read words through
`Int256.toInt (Int256.ofUint256 (Uint256.ofNat w))`; rewrite those with
`toInt_ofI`. Keep `2 ^ 256` unevaluated: once it becomes a 78-digit literal,
`Int.emod` rewrites stop matching.
-/

open Compiler.CompilationModel Compiler.CompilationModel.Denote
open Verity.Core

namespace ProofKit

/-- The word holding `a` modulo `2^256`. -/
def ofI (a : Int) : Nat := (a % 2 ^ 256).toNat

theorem ofI_cast (a : Int) : ((ofI a : Nat) : Int) = a % 2 ^ 256 := by
  unfold ofI
  exact Int.toNat_of_nonneg (Int.emod_nonneg _ (by omega))

theorem ofI_lt (a : Int) : ofI a < 2 ^ 256 := by
  have h := ofI_cast a
  have h2 : a % 2 ^ 256 < 2 ^ 256 := Int.emod_lt_of_pos _ (by omega)
  omega

theorem ofI_eq_iff (a b : Int) : ofI a = ofI b ↔ a % 2 ^ 256 = b % 2 ^ 256 := by
  constructor
  · intro h; rw [← ofI_cast, ← ofI_cast, h]
  · intro h; unfold ofI; rw [h]

theorem ofI_natCast (n : Nat) (h : n < 2 ^ 256) : ofI (n : Int) = n := by
  have h1 := ofI_cast n
  have h2 : (n : Int) % 2 ^ 256 = n := Int.emod_eq_of_lt (by omega) (by exact_mod_cast h)
  omega

theorem ofI_of_nonneg (a : Int) (h0 : 0 ≤ a) (h : a < 2 ^ 256) : ofI a = a.toNat := by
  unfold ofI; rw [Int.emod_eq_of_lt h0 h]

theorem cast_two_pow_256 : ((2 ^ 256 : Nat) : Int) = 2 ^ 256 := by
  rw [Int.natCast_pow]; rfl

theorem natCast_ofI (n : Nat) : ofI (n : Int) = n % 2 ^ 256 := by
  have h1 := ofI_cast n
  have h2 : ((n % 2 ^ 256 : Nat) : Int) = (n : Int) % 2 ^ 256 := by
    rw [Int.natCast_emod, cast_two_pow_256]
  omega

theorem wordNormalize_eq (n : Nat) : wordNormalize n = ofI (n : Int) := by
  rw [natCast_ofI]; rfl

theorem wadd_ofI (a b : Int) : wadd (ofI a) (ofI b) = ofI (a + b) := by
  show (ofI a % 2 ^ 256 + ofI b % 2 ^ 256) % 2 ^ 256 = ofI (a + b)
  rw [Nat.mod_eq_of_lt (ofI_lt a), Nat.mod_eq_of_lt (ofI_lt b)]
  have h1 := ofI_cast a
  have h2 := ofI_cast b
  have h3 := ofI_cast (a + b)
  have : (((ofI a + ofI b) % 2 ^ 256 : Nat) : Int) = ((ofI (a + b) : Nat) : Int) := by
    rw [Int.natCast_emod, Int.natCast_add, h1, h2, h3, cast_two_pow_256, ← Int.add_emod]
  exact_mod_cast this

theorem wmul_ofI (a b : Int) : wmul (ofI a) (ofI b) = ofI (a * b) := by
  show (ofI a % 2 ^ 256 * (ofI b % 2 ^ 256)) % 2 ^ 256 = ofI (a * b)
  rw [Nat.mod_eq_of_lt (ofI_lt a), Nat.mod_eq_of_lt (ofI_lt b)]
  have h1 := ofI_cast a
  have h2 := ofI_cast b
  have h3 := ofI_cast (a * b)
  have : (((ofI a * ofI b) % 2 ^ 256 : Nat) : Int) = ((ofI (a * b) : Nat) : Int) := by
    rw [Int.natCast_emod, Int.natCast_mul, h1, h2, h3, cast_two_pow_256, ← Int.mul_emod]
  exact_mod_cast this

theorem wsub_ofI (a b : Int) : wsub (ofI a) (ofI b) = ofI (a - b) := by
  show (Uint256.sub (Uint256.ofNat (ofI a)) (Uint256.ofNat (ofI b))).val = ofI (a - b)
  unfold Uint256.sub
  have ha := ofI_lt a
  have hb := ofI_lt b
  have h1 := ofI_cast a
  have h2 := ofI_cast b
  have h3 := ofI_cast (a - b)
  have hsub : (a - b) % 2 ^ 256 = (a % 2 ^ 256 - b % 2 ^ 256) % 2 ^ 256 := Int.sub_emod _ _ _
  simp only [Uint256.val_ofNat, Uint256.modulus, UINT256_MODULUS, Nat.mod_eq_of_lt ha,
    Nat.mod_eq_of_lt hb]
  split
  · rename_i h
    show (ofI a - ofI b) % 2 ^ 256 = ofI (a - b)
    rw [Nat.mod_eq_of_lt (by omega)]
    have : (a % 2 ^ 256 - b % 2 ^ 256) % 2 ^ 256 = a % 2 ^ 256 - b % 2 ^ 256 :=
      Int.emod_eq_of_lt (by omega) (by omega)
    omega
  · rename_i h
    show (2 ^ 256 - (ofI b - ofI a)) % 2 ^ 256 = ofI (a - b)
    rw [Nat.mod_eq_of_lt (by omega)]
    have : (a % 2 ^ 256 - b % 2 ^ 256) % 2 ^ 256 = a % 2 ^ 256 - b % 2 ^ 256 + 2 ^ 256 := by
      omega
    omega

/-- A word read as `int256`. -/
theorem toInt_ofI (a : Int) (h1 : -2 ^ 255 ≤ a) (h2 : a < 2 ^ 255) :
    Int256.toInt (Int256.ofUint256 (Uint256.ofNat (ofI a))) = a := by
  have hc := ofI_cast a
  have hl := ofI_lt a
  unfold Int256.toInt
  simp only [Int256.ofUint256, Uint256.val_ofNat, Uint256.modulus, UINT256_MODULUS,
    Nat.mod_eq_of_lt hl, Int256.signBit, Int256.modulus, Int.ofNat_eq_natCast]
  by_cases ha : 0 ≤ a
  · have : a % 2 ^ 256 = a := Int.emod_eq_of_lt ha (by omega)
    rw [if_pos (by omega)]; omega
  · have : a % 2 ^ 256 = a + 2 ^ 256 := by
      omega
    rw [if_neg (by omega)]; rw [Int.natCast_pow]; omega

theorem word_eq_ofI (x : Int256) : x.toUint256.val = ofI x.toInt := by
  have hl : x.word.val < 2 ^ 256 := x.word.isLt
  have hc := ofI_cast x.toInt
  have ht : x.toInt = (x.word.val : Int) ∨ x.toInt = (x.word.val : Int) - 2 ^ 256 := by
    unfold Int256.toInt
    simp only [Int256.signBit, Int256.modulus, Uint256.modulus, UINT256_MODULUS,
      Int.ofNat_eq_natCast]
    split
    · left; rfl
    · right; rw [Int.natCast_pow]; rfl
  show x.word.val = _
  rcases ht with h | h <;> omega

theorem ofInt_val (a : Int) (h1 : -2 ^ 255 ≤ a) (h2 : a < 2 ^ 255) :
    (Int256.ofInt a).toUint256.val = ofI a := by
  have hc := ofI_cast a
  unfold Int256.ofInt
  split
  · rename_i h
    simp only [Int256.toUint256_ofUint256, Uint256.val_ofNat, Uint256.modulus, UINT256_MODULUS,
      Int256.modulus]
    have : a % 2 ^ 256 = a + 2 ^ 256 := by
      omega
    have hn : a.natAbs % 2 ^ 256 = a.natAbs := Nat.mod_eq_of_lt (by omega)
    rw [hn, Nat.mod_eq_of_lt (by omega)]
    omega
  · rename_i h
    simp only [Int256.toUint256_ofUint256, Uint256.val_ofNat, Uint256.modulus, UINT256_MODULUS]
    have : a % 2 ^ 256 = a := Int.emod_eq_of_lt (by omega) (by omega)
    rw [Nat.mod_eq_of_lt (by omega)]
    omega

/-- Signed division of two in-range words truncates toward zero. -/
theorem sdiv_ofI (a b : Int) (ha1 : -2 ^ 255 < a) (ha2 : a < 2 ^ 255)
    (hb1 : -2 ^ 255 < b) (hb2 : b < 2 ^ 255) (hb : b ≠ 0) :
    (Int256.div (Int256.ofUint256 (Uint256.ofNat (ofI a)))
      (Int256.ofUint256 (Uint256.ofNat (ofI b)))).toUint256.val = ofI (a.tdiv b) := by
  unfold Int256.div
  simp only [toInt_ofI a (by omega) ha2, toInt_ofI b (by omega) hb2, if_neg hb,
    Int256.signedAbsNat]
  have hn : (a.tdiv b).natAbs = a.natAbs / b.natAbs := Int.natAbs_tdiv a b
  have hq : (a.natAbs / b.natAbs : Nat) ≤ a.natAbs := Nat.div_le_self _ _
  have hle : (a.tdiv b).natAbs ≤ a.natAbs := by omega
  split
  · rename_i hs
    have heq : ((a.natAbs / b.natAbs : Nat) : Int) = a.tdiv b := by
      rw [← hn]
      have : 0 ≤ a.tdiv b := by
        simp only [beq_iff_eq, decide_eq_decide] at hs
        rcases Int.lt_or_le a 0 with h | h <;> rcases Int.lt_or_le b 0 with h' | h'
        · exact Int.tdiv_nonneg_of_nonpos_of_nonpos (by omega) (by omega)
        · exact absurd (hs.mp h) (by omega)
        · exact absurd (hs.mpr h') (by omega)
        · exact Int.tdiv_nonneg h h'
      omega
    rw [Int.ofNat_eq_natCast, heq, ofInt_val _ (by omega) (by omega)]
  · rename_i hs
    have heq : -((a.natAbs / b.natAbs : Nat) : Int) = a.tdiv b := by
      rw [← hn]
      have : a.tdiv b ≤ 0 := by
        simp only [beq_iff_eq, decide_eq_decide] at hs
        rcases Int.lt_or_le a 0 with h | h <;> rcases Int.lt_or_le b 0 with h' | h'
        · exact absurd ⟨fun _ => h', fun _ => h⟩ hs
        · have h2 : 0 ≤ (-a).tdiv b := Int.tdiv_nonneg (by omega) h'
          rw [Int.neg_tdiv] at h2; omega
        · exact Int.tdiv_nonpos_of_nonneg_of_nonpos h (by omega)
        · exact absurd ⟨fun h1 => absurd h1 (by omega), fun h1 => absurd h1 (by omega)⟩ hs
      omega
    rw [Int.ofNat_eq_natCast, heq, ofInt_val _ (by omega) (by omega)]

/-- `shl` of a small nonnegative value by a small shift. -/
theorem shl_ofI (q e : Int) (hq0 : 0 ≤ q) (hq : q < 256) (he0 : 0 ≤ e) (he : e < 2 ^ 256) :
    (Uint256.shl (Uint256.ofNat (ofI q)) (Uint256.ofNat (ofI e))).val =
      (e.toNat * 2 ^ q.toNat) % 2 ^ 256 := by
  rw [ofI_of_nonneg q hq0 (by omega), ofI_of_nonneg e he0 he]
  unfold Uint256.shl
  simp only [Uint256.val_ofNat, Uint256.modulus, UINT256_MODULUS, Nat.shiftLeft_eq]
  rw [Nat.mod_eq_of_lt (a := q.toNat) (by omega), Nat.mod_eq_of_lt (a := e.toNat) (by omega)]

theorem ofI_ne_lit (a b : Int) (ha0 : 0 ≤ a) (ha : a < 2 ^ 256) (hb0 : 0 ≤ b) (hb : b < 2 ^ 256)
    (h : a ≠ b) : (ofI a = ofI b) = False := by
  rw [ofI_eq_iff, Int.emod_eq_of_lt ha0 ha, Int.emod_eq_of_lt hb0 hb]; simp [h]

theorem ofI_le_ofI (a b : Int) (ha0 : 0 ≤ a) (ha : a < 2 ^ 256) (hb0 : 0 ≤ b)
    (hb : b < 2 ^ 256) : (ofI a ≤ ofI b) = (a ≤ b) := by
  rw [ofI_of_nonneg a ha0 ha, ofI_of_nonneg b hb0 hb]
  apply propext; omega

/-- Unsigned division of nonnegative in-range values is `Int` division. -/
theorem wdiv_ofI (a b : Int) (ha0 : 0 ≤ a) (ha : a < 2 ^ 256) (hb0 : 0 ≤ b)
    (hb : b < 2 ^ 256) : wdiv (ofI a) (ofI b) = ofI (a / b) := by
  rw [wdiv_of_lt _ _ (ofI_lt a) (ofI_lt b), ofI_of_nonneg a ha0 ha, ofI_of_nonneg b hb0 hb]
  have h1 : 0 ≤ a / b := Int.ediv_nonneg ha0 hb0
  have h2 : a / b ≤ a := Int.ediv_le_self b ha0
  rw [ofI_of_nonneg _ h1 (by omega)]
  obtain ⟨a, rfl⟩ := Int.eq_ofNat_of_zero_le ha0
  obtain ⟨b, rfl⟩ := Int.eq_ofNat_of_zero_le hb0
  rfl

theorem ofI_cast_ofI (a : Int) : ofI ((ofI a : Nat) : Int) = ofI a := by
  rw [ofI_natCast _ (ofI_lt a)]

/-- `shl_ofI` with the result as `ofI` of an `Int` product. -/
theorem shl_ofI_mul (q e : Int) (hq0 : 0 ≤ q) (hq : q < 256) (he0 : 0 ≤ e) (he : e < 2 ^ 256) :
    (Uint256.shl (Uint256.ofNat (ofI q)) (Uint256.ofNat (ofI e))).val =
      ofI (e * 2 ^ q.toNat) := by
  rw [shl_ofI q e hq0 hq he0 he, ← natCast_ofI]
  congr 1
  rw [Int.natCast_mul, Int.natCast_pow, Int.toNat_of_nonneg he0]
  rfl

/-- Truncated division by a positive divisor, as floor division. -/
theorem tdiv_cases (m b : Int) (_hb : 0 < b) :
    (m.tdiv b = m / b ∧ 0 ≤ m) ∨ (m.tdiv b = -((-m) / b) ∧ m < 0) := by
  rcases Int.lt_or_le m 0 with h | h
  · right; refine ⟨?_, h⟩
    rw [← Int.tdiv_eq_ediv_of_nonneg (by omega), Int.neg_tdiv, Int.neg_neg]
  · left; exact ⟨Int.tdiv_eq_ediv_of_nonneg h, h⟩

/-! ## `run_sexec`

`run_exec` for signed code. State the run with every word as `ofI a` for an
`Int` term `a`: wrapping arithmetic then needs no side condition, and only
signed comparisons and divisions, shifts and literal tests need range facts,
which `omega` discharges from hypotheses in the context. Literals become
`ofI` through `wordNormalize_eq`. Takes extra lemmas and a location like
`run_exec`. -/

syntax (name := runSExec) "run_sexec" (" [" Lean.Parser.Tactic.simpLemma,* "]")?
  (Lean.Parser.Tactic.location)? : tactic

macro_rules
  | `(tactic| run_sexec $[$loc]?) => `(tactic| run_sexec [] $[$loc]?)
  | `(tactic| run_sexec [$extra,*] $[$loc]?) => `(tactic|
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
         ProofKit.eval_ge, ProofKit.eval_logicalNot,
         ProofKit.eval_slt, ProofKit.eval_sgt, ProofKit.eval_sdiv, ProofKit.eval_shl,
         Option.bind_some,
         ProofKit.lookup_bind_same,
         ProofKit.lookup_bind_ne, ProofKit.lookup_single, String.reduceBEq,
         ProofKit.boolWord_ne_zero, decide_eq_true_eq, decide_eq_false_iff_not,
         ProofKit.wordNormalize_eq, Int.cast_ofNat_Int, Int.natCast_zero, Int.natCast_one,
         ProofKit.wadd_ofI, ProofKit.wsub_ofI, ProofKit.wmul_ofI, ProofKit.sdiv_ofI,
         ProofKit.wdiv_ofI, ProofKit.ofI_le_ofI, ProofKit.ofI_cast_ofI,
         ProofKit.toInt_ofI, ProofKit.shl_ofI_mul, ProofKit.ofI_ne_lit,
         if_pos, if_neg, ite_self, ite_false, ite_true, not_false_eq_true,
         StmtOutcome.continue.injEq, StmtOutcome.stop.injEq, exists_eq_left',
         Option.some.injEq, List.cons.injEq, and_true, $extra,*] $[$loc]?)

end ProofKit
