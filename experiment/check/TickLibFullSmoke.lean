import Midnight.TickLibFullSpec

open Compiler.CompilationModel.Denote
open Verity.Core

private def oracle : DenoteOracle where
  mappingSlot _ _ := 0
  keccakMemorySlice _ _ _ := 0

-- Exercise the generated functions, not a separate Lean implementation.
-- Expected values are those of the Solidity's arithmetic.
private def checkSamples : IO Unit := do
  let w := Verity.defaultState
  let wexp : List (Int × Option Nat) :=
    [(0, some 1000000000000000000),
     (-1, some 999999999999999999),
     (16817989975223754156, some 20134595243400876315901952),
     (-16817989975223754156, some 49665761238),
     (135999161806159974428,
      some 115792089237316195323137357242501015631897353894317901381819896896488577433600),
     (135999161806159974429, some 0),
     (-135999161806159974429, none)]
  for (input, expected) in wexp do
    let actual := (tickLibFull.wExp oracle w (Int256.ofInt input)).map (·.val)
    unless actual == expected do
      throw (IO.userError s!"Imported wExp({input}) returned {repr actual}; expected {repr expected}")
  let ticks : List (Nat × Option Nat) :=
    [(0, some 0), (3372, some 500000000000000000), (6743, some 1000000000000000000),
     (6744, some 1000000000000000000), (6745, none)]
  for (input, expected) in ticks do
    let actual := (tickLibFull.tickToPrice oracle w (Uint256.ofNat input)).map (·.val)
    unless actual == expected do
      throw (IO.userError s!"Imported tickToPrice({input}) returned {repr actual}; expected {repr expected}")
  IO.println "Imported TickLib smoke tests passed (wExp at 0, ±maxInput, ±xStar; tickToPrice at 0, 3372, 6743, 6744, 6745)"

#eval checkSamples

#print axioms tickLibFull.covered
