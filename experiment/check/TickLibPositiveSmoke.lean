import Midnight.TickLibPositiveSpec

open Compiler.CompilationModel.Denote
open Verity.Core

private def oracle : DenoteOracle where
  mappingSlot _ _ := 0
  keccakMemorySlice _ _ _ := 0

-- Exercise the generated function, not a separate Lean implementation.
private def checkSamples : IO Unit := do
  let samples : List (Nat × Nat) :=
    [(0, 1000000000000000000),
     (1, 1000000000000000001),
     (693147180559945309, 2000000000000000000),
     (16817989975223754156, 20134595243400876315901952)]
  for (input, expected) in samples do
    let actual := tickLibPositive.wExp oracle Verity.defaultState (Uint256.ofNat input)
    unless actual.map (·.val) == some expected do
      throw (IO.userError s!"Imported wExp({input}) returned {repr actual}; expected {expected}")
  IO.println "Imported wExp smoke tests passed (zero, one, zero residual, maximum input)"

#eval checkSamples

#print axioms tickLibPositive.covered
