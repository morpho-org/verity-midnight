import Midnight.TickLibImport

/-!
# Monotonicity of Midnight's original `TickLib.wExp`

This specification executes the model that `Midnight/TickLibImport.lean`
generates from the unmodified Solidity (`vendor/midnight/src/libraries/TickLib.sol`),
following the successful-call style of `Midnight/Spec.lean`.

The range is `[-maxInput, maxInput]`, where
`maxInput = LN_ONE_PLUS_DELTA * (MAX_TICK / 2)`: the inputs `tickToPrice`
passes to `wExp` for valid ticks, as in `Midnight/TickLibSpec.lean`. It includes
every integer in that interval, not only those obtained from integer ticks.
An unrestricted claim over all `int256` inputs would be false: the Solidity
uses unchecked arithmetic and a left shift that can discard bits.
Order on inputs is signed (`Int256.toInt`); outputs are unsigned.

`wExpIsMonotonic` states that successful outputs are non-decreasing.
`wExpSucceeds` separately states that every input in range succeeds, so a full
verification also rules out reverts and panics. Neither proposition is proved
in this file.
-/

open Compiler.CompilationModel.Denote
open Verity.Core

namespace Midnight.Spec.TickLibImport

/-- `LN_ONE_PLUS_DELTA * (MAX_TICK / 2)` for the TickLib constants. -/
def maxInput : Int := 4987541511039073 * (6744 / 2)

/-- Inputs used by `tickToPrice` lie in this interval. -/
def inRange (x : Int256) : Prop :=
  -maxInput ≤ x.toInt ∧ x.toInt ≤ maxInput

/-- The generated function succeeds on the whole input range. -/
def wExpSucceeds : Prop :=
  ∀ (oracle : DenoteOracle) (world : Verity.ContractState) (x : Int256),
    inRange x → ∃ result, tickLib.wExp oracle world x = some result

/-- `x > y` implies `wExp(x) ≥ wExp(y)` for successful calls in range. -/
def wExpIsMonotonic : Prop :=
  ∀ (oracle : DenoteOracle) (world : Verity.ContractState)
    (x y : Int256) (expX expY : Uint256),
    inRange x → inRange y →
    y.toInt < x.toInt →
    tickLib.wExp oracle world x = some expX →
    tickLib.wExp oracle world y = some expY →
    expY.val ≤ expX.val

end Midnight.Spec.TickLibImport
