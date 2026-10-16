import Compiler.SolidityImport.Import

/-!
Import the unsigned, non-recursive Solidity implementation. The importer creates
`tickLibPositive.model`, `tickLibPositive.covered`, `tickLibPositive.sourceDigest`,
and `tickLibPositive.wExp : DenoteOracle → ContractState → Uint256 → Option Uint256`.
There is no handwritten Lean implementation of the exponential here.
-/

solidity_import tickLibPositive from "solidity" entry "TickLibPositive.sol"
  using { evmVersion := "osaka", viaIR := true, optimizerRuns := some 466, bytecodeHash := "none" }
  contract TickLibPositive
  function wExp(uint256)
