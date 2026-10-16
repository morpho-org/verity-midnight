import Midnight.TickLibFullImport

/-!
# TickLib: `wExp` and `tickToPrice` rules

Nine properties of Midnight's original `TickLib.wExp` and `TickLib.tickToPrice`,
stated on the model `Midnight/TickLibFullImport.lean` generates from the
unmodified Solidity. They port the rules of
`vendor/midnight/certora/specs/TickToPrice.spec` and
`vendor/midnight/certora/specs/TickToPriceIsMonotonic.spec`, plus two that
pin the exact range of `wExp`'s monotonicity and the totality of `tickToPrice`.

## Differences with the CVL rules

- **No summary of `wExp`.** `TickToPriceIsMonotonic.spec` replaces `wExp` by a
  ghost that is assumed monotone on all of `int256`. That assumption is false
  beyond `xStar` (see `wExpNotMonotonicBeyond`). Here `tickToPrice` runs the
  imported `wExp` itself.
- **Successful calls.** A CVL call without `@withrevert` only considers
  non-reverting executions; here that is a hypothesis `… = some p`. The
  concrete rules (`tickToPriceIsZeroAtZero`, ...) also require the call to
  succeed, and `wExpIsMonotonic` and `tickToPriceTotal` state success
  explicitly, so no property holds merely because a call reverts.
- **Ranges.** `wExpIsMonotonic` covers `[-xStar, xStar]`, which contains the
  inputs `tickToPrice` produces (`[-maxInput, maxInput]`) and is the exact
  limit. The CVL wExp rules cover `[-maxInput, maxInput]`.

Inputs of `wExp` are ordered as signed integers (`Int256.toInt`); outputs are
unsigned. Constants are those of `TickLib.sol`. None of the propositions is
proved in this file.
-/

open Compiler.CompilationModel.Denote
open Verity.Core

namespace Midnight.Spec.TickLibFull

/-- `MAX_TICK`. -/
def maxTick : Nat := 6744

/-- `PRICE_ROUNDING_STEP`. -/
def priceRoundingStep : Nat := 100000000000

/-- `1e18`. -/
def wad : Nat := 1000000000000000000

/-- `LN_ONE_PLUS_DELTA * (MAX_TICK / 2)`: the largest `|input|` of `wExp` in `tickToPrice`. -/
def maxInput : Int := 4987541511039073 * (6744 / 2)

/-- `maxOutput()` of `TickToPrice.spec`. -/
def maxOutput : Nat := 20134595243400876315901952

/-- The largest input on which `wExp` is non-decreasing. -/
def xStar : Int := 135999161806159974428

/-- On `[-xStar, xStar]`, both calls succeed and `x ≤ y → wExp(x) ≤ wExp(y)`. -/
def wExpIsMonotonic : Prop :=
  ∀ (oracle : DenoteOracle) (world : Verity.ContractState) (x y : Int256),
    -xStar ≤ x.toInt → x.toInt ≤ y.toInt → y.toInt ≤ xStar →
    ∃ expX expY,
      tickLibFull.wExp oracle world x = some expX ∧
      tickLibFull.wExp oracle world y = some expY ∧
      expX.val ≤ expY.val

/-- `xStar` is the exact limit: `wExp(xStar) > wExp(xStar + 1) = 0`. -/
def wExpNotMonotonicBeyond : Prop :=
  ∀ (oracle : DenoteOracle) (world : Verity.ContractState),
    ∃ e : Uint256,
      tickLibFull.wExp oracle world (Int256.ofInt xStar) = some e ∧
      tickLibFull.wExp oracle world (Int256.ofInt (xStar + 1)) = some 0 ∧
      0 < e.val

/-- `rule maxOutputIsWExpOfMaxInput`: `maxOutput() == wExp(maxInput())`. -/
def maxOutputIsWExpOfMaxInput : Prop :=
  ∀ (oracle : DenoteOracle) (world : Verity.ContractState),
    (tickLibFull.wExp oracle world (Int256.ofInt maxInput)).map (·.val) = some maxOutput

/-- `rule tickToPriceIsMonotonic`: `tick1 < tick2 => tickToPrice(tick1) <= tickToPrice(tick2)`. -/
def tickToPriceIsMonotonic : Prop :=
  ∀ (oracle : DenoteOracle) (world : Verity.ContractState) (tick1 tick2 price1 price2 : Uint256),
    tick1.val < tick2.val →
    tickLibFull.tickToPrice oracle world tick1 = some price1 →
    tickLibFull.tickToPrice oracle world tick2 = some price2 →
    price1.val ≤ price2.val

/-- `rule tickToPriceIsZeroAtZero`: `tickToPrice(0) == 0`. -/
def tickToPriceIsZeroAtZero : Prop :=
  ∀ (oracle : DenoteOracle) (world : Verity.ContractState),
    (tickLibFull.tickToPrice oracle world (Uint256.ofNat 0)).map (·.val) = some 0

/-- `rule tickToPriceIsOneAtMaxTick`: `tickToPrice(maxTick()) == 10 ^ 18`. -/
def tickToPriceIsOneAtMaxTick : Prop :=
  ∀ (oracle : DenoteOracle) (world : Verity.ContractState),
    (tickLibFull.tickToPrice oracle world (Uint256.ofNat maxTick)).map (·.val) = some wad

/-- `rule tickToPriceUsesPriceRoundingStep`: `tickToPrice(tick) % priceRoundingStep() == 0`. -/
def tickToPriceUsesPriceRoundingStep : Prop :=
  ∀ (oracle : DenoteOracle) (world : Verity.ContractState) (tick price : Uint256),
    tickLibFull.tickToPrice oracle world tick = some price →
    price.val % priceRoundingStep = 0

/-- `rule tickToPriceAtMostWad`: `tickToPrice(tick) <= 10 ^ 18`. -/
def tickToPriceAtMostWad : Prop :=
  ∀ (oracle : DenoteOracle) (world : Verity.ContractState) (tick price : Uint256),
    tickLibFull.tickToPrice oracle world tick = some price →
    price.val ≤ wad

/-- Every tick up to `MAX_TICK` succeeds. -/
def tickToPriceTotal : Prop :=
  ∀ (oracle : DenoteOracle) (world : Verity.ContractState) (tick : Uint256),
    tick.val ≤ maxTick → ∃ price, tickLibFull.tickToPrice oracle world tick = some price

end Midnight.Spec.TickLibFull
