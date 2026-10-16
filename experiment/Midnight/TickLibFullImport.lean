import Compiler.SolidityImport.Import

/-!
Import Midnight's original `TickLib.wExp(int256)` and `TickLib.tickToPrice(uint256)`
from `vendor/midnight/src/libraries/TickLib.sol`, unmodified, through Morpho's
Certora harness `vendor/midnight/certora/helpers/TickLibWrapper.sol`. The
importer creates `tickLibFull.model`, `tickLibFull.covered` and the typed
wrappers
`tickLibFull.wExp : DenoteOracle → ContractState → Int256 → Option Uint256` and
`tickLibFull.tickToPrice : DenoteOracle → ContractState → Uint256 → Option Uint256`.
`tickToPrice`'s call of `wExp`, and `wExp`'s recursive call, are inlined.
There is no handwritten Lean implementation here.
-/

solidity_import tickLibFull from "vendor/midnight" entry "certora/helpers/TickLibWrapper.sol"
  using { evmVersion := "osaka", viaIR := true, optimizerRuns := some 466, bytecodeHash := "none" }
  contract TickLibWrapper
  function wExp(int256)
  function tickToPrice(uint256)
