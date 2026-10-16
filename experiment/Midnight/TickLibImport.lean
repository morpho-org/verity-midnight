import Compiler.SolidityImport.Import

/-!
Import Midnight's original `TickLib.wExp(int256)` from
`vendor/midnight/src/libraries/TickLib.sol`, unmodified, through Morpho's
Certora harness `vendor/midnight/certora/helpers/TickLibWrapper.sol`, whose
`wExp(int256 x)` returns `TickLib.wExp(x)`. The importer creates `tickLib.model`,
`tickLib.covered`, `tickLib.sourceDigest`, and
`tickLib.wExp : DenoteOracle → ContractState → Int256 → Option Uint256`.
The recursive call of the negative branch is inlined by the importer.
There is no handwritten Lean implementation of the exponential here.
-/

solidity_import tickLib from "vendor/midnight" entry "certora/helpers/TickLibWrapper.sol"
  using { evmVersion := "osaka", viaIR := true, optimizerRuns := some 466, bytecodeHash := "none" }
  contract TickLibWrapper
  function wExp(int256)
