import Verity.Core.Int256

/-!
# `TickLib.wExp` is monotonically non-decreasing

For any signed inputs in the range used by `tickToPrice`,
`x > y → wExp x ≥ wExp y`. This states the combined monotonicity claim from
`vendor/midnight/certora/specs/TickToPrice.spec`, including the negative
range, the crossing at zero, and the positive range's segment boundaries.

The range is `[-maxInput, maxInput]`, where
`maxInput = LN_ONE_PLUS_DELTA * (MAX_TICK / 2)`. It includes every integer
in that interval, not only the inputs obtained from integer ticks.
An unrestricted claim over all `int256` inputs would be false: the Solidity
uses unchecked arithmetic and a 256-bit left shift that can discard bits.

## Model

Unlike `Midnight/Spec.lean`, this file uses an explicit translation of
`vendor/midnight/src/libraries/TickLib.sol`, rather than `solidity_import`.
The pinned importer does not support `int256` parameters and rejects recursive
calls. No equivalence theorem connecting this translation to Solidity is
claimed here.

The model uses Verity's `Int256` and `Uint256`: arithmetic wraps at 256 bits,
signed division truncates toward zero, and casts reinterpret the word.
This is a pure value model on the specified input range. The recursive negative
branch is unfolded once. Outside that range, recursive nontermination at the
minimum signed value and Solidity's zero-divisor panic are not modeled;
Verity's unsigned division returns zero for a zero divisor.

`wExpIsMonotonic` below is a specification (`Prop`), not a proof.
-/

open Verity.Core

namespace Midnight.TickLib

/-- The Solidity constant `LN_ONE_PLUS_DELTA`, in WAD units. -/
def lnOnePlusDelta : Int := 4987541511039073

/-- The Solidity constant `MAX_TICK`. -/
def maxTick : Nat := 6744

/-- Largest absolute input used by `tickToPrice` for a valid tick. -/
def maxInput : Int := lnOnePlusDelta * (maxTick / 2 : Nat)

/-- The `else` branch of Solidity's `wExp`, with unchecked word arithmetic. -/
def wExpNonnegative (x : Int256) : Uint256 :=
  let ln2 : Int256 := 693147180559945309
  let offset : Int256 := 322611214989459870
  let q := (x + offset) / ln2
  let r := x - q * ln2
  let wad : Int256 := 1000000000000000000
  let secondTerm := r * r / (2 * wad)
  let thirdTerm := secondTerm * r / (3 * wad)
  let expR := wad + r + secondTerm + thirdTerm
  let shift := q.toUint256
  -- EVM shifts by 256 or more return zero. Avoid constructing enormous Nats.
  if shift.val ≥ 256 then 0 else Uint256.shl shift expR.toUint256

/-- Pure value model of Solidity's `wExp(int256)` on the tick input range. -/
def wExp (x : Int256) : Uint256 :=
  if x < 0 then
    (1000000000000000000000000000000000000 : Uint256) / wExpNonnegative (-x)
  else wExpNonnegative x

end Midnight.TickLib

namespace Midnight.Spec

/-- Inputs used by `tickToPrice` lie in this interval. -/
def inWExpRange (x : Int256) : Prop :=
  -TickLib.maxInput ≤ x.toInt ∧ x.toInt ≤ TickLib.maxInput

/-- Increasing the signed input cannot decrease the unsigned output. -/
def wExpIsMonotonic : Prop :=
  ∀ (x y : Int256),
    inWExpRange x → inWExpRange y →
    x > y → TickLib.wExp x ≥ TickLib.wExp y

end Midnight.Spec
