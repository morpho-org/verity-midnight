import Midnight.Spec

/-!
Run the imported `updatePositionView` on concrete ABI-encoded call data, so the
specification's call is known to succeed on real input (the claim is not
vacuous) and to revert on input the Solidity decoder rejects.
-/

open Compiler.CompilationModel.Denote
open Compiler.CompilationModel.SolidityImport
open Verity.Core

private def oracle : DenoteOracle where
  mappingSlot _ _ := 0
  keccakMemorySlice _ _ _ := 0

/-- ABI encoding of `(Market, bytes32 id, address user)` after the selector,
with an empty `collateralParams` array. -/
private def calldata (id user maturity : Nat) : List Nat :=
  [ 96, id, user,                      -- head: offset of `market`, `id`, `user`
    1, 2, 3, 256, maturity, 0, 4, 5,   -- `market`: chainId .. liquidatorGate
    0 ]                                -- `collateralParams.length`

private def world (data : List Nat) : Verity.ContractState :=
  { Verity.defaultState with
    calldata := data, calldataSize := Uint256.ofNat (4 + 32 * data.length) }

private def checkCalls : IO Unit := do
  let w := world (calldata 7 8 1000)
  let ok := runFunction oracle midnight.model "updatePositionView" w []
  unless ok == some [0, 0, 0] do
    throw (IO.userError s!"updatePositionView on empty storage returned {repr ok}")
  unless Midnight.Spec.argWord w 36 == 7 && Midnight.Spec.argWord w 68 == 8 do
    throw (IO.userError "argWord does not read id and user from the call data")
  let badUser := runFunction oracle midnight.model "updatePositionView"
    (world (calldata 7 (2 ^ 160) 1000)) []
  unless badUser == none do
    throw (IO.userError s!"an out-of-range user was accepted: {repr badUser}")
  IO.println "Imported updatePositionView smoke tests passed (success on empty storage, revert on bad address)"

#eval checkCalls

#print axioms midnight.covered
