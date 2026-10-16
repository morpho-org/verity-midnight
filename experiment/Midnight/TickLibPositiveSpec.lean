import Midnight.TickLibPositiveImport

/-!
# Monotonicity of the imported unsigned Solidity exponential

This specification executes the model generated from `solidity/TickLibPositive.sol`,
following the successful-call style of `Midnight/Spec.lean`. Both inputs are in the
positive tick range. Inputs use unsigned order; zero is included.

`wExpIsMonotonic` states that successful outputs are non-decreasing.
`wExpSucceeds` separately states that every input in range succeeds, so a full
verification can also rule out arithmetic reverts. Neither proposition is proved
in this file.

This imports a new Solidity implementation. Equivalence to the original signed
`vendor/midnight/src/libraries/TickLib.sol` is a separate claim, not established
by importing the new implementation or by proving its monotonicity.
-/

open Compiler.CompilationModel.Denote
open Verity.Core

namespace Midnight.Spec.TickLibPositive

/-- `LN_ONE_PLUS_DELTA * (MAX_TICK / 2)` for the original TickLib constants. -/
def maxInput : Nat := 4987541511039073 * (6744 / 2)

/-- The generated function succeeds on the intended input range. -/
def wExpSucceeds : Prop :=
  ∀ (oracle : DenoteOracle) (world : Verity.ContractState) (x : Uint256),
    x.val ≤ maxInput → ∃ result, tickLibPositive.wExp oracle world x = some result

/-- `x > y` implies `wExp(x) ≥ wExp(y)` for successful calls in the positive range. -/
def wExpIsMonotonic : Prop :=
  ∀ (oracle : DenoteOracle) (world : Verity.ContractState)
    (x y expX expY : Uint256),
    x.val ≤ maxInput →
    x > y →
    tickLibPositive.wExp oracle world x = some expX →
    tickLibPositive.wExp oracle world y = some expY →
    expX ≥ expY

end Midnight.Spec.TickLibPositive
