import Compiler.SolidityImport.Import

/-!
`Midnight.updatePositionView` at `morpho-org/midnight@96d31343`, imported from
the Solidity source. This produces `midnight.model : CompilationModel`, which
`Spec.lean` executes and `Proof.lean` reasons about.
-/

solidity_import midnight from "vendor/midnight" entry "src/Midnight.sol"
  using { evmVersion := "osaka", viaIR := true, optimizerRuns := some 466, bytecodeHash := "none" }
  contract Midnight
  function updatePositionView(Market, bytes32, address)
