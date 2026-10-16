import Midnight.TickLibImportSpec

open Compiler.CompilationModel.Denote
open Verity.Core

private def oracle : DenoteOracle where
  mappingSlot _ _ := 0
  keccakMemorySlice _ _ _ := 0

-- Exercise the generated function, not a separate Lean implementation.
-- Expected values are those of the Solidity's unchecked int256 arithmetic.
private def checkSamples : IO Unit := do
  let samples : List (Int × Nat) :=
    [(0, 1000000000000000000),
     (1, 1000000000000000001),
     (-1, 999999999999999999),
     (693147180559945309, 2000000000000000000),
     (-693147180559945309, 500000000000000000),
     (16817989975223754156, 20134595243400876315901952),
     (-16817989975223754156, 49665761238)]
  for (input, expected) in samples do
    let actual := tickLib.wExp oracle Verity.defaultState (Int256.ofInt input)
    unless actual.map (·.val) == some expected do
      throw (IO.userError s!"Imported wExp({input}) returned {repr actual}; expected {expected}")
  IO.println "Imported original wExp smoke tests passed (zero, ±1, ±ln2, ±maximum input)"

#eval checkSamples

#print axioms tickLib.covered
