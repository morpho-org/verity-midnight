import Lake
open Lake DSL

package «morpho-midnight-verity» where
  version := v!"0.1.0"

require verity from git "https://github.com/lfglabs-dev/verity" @ "9b472a8a48a9990337845f1720a20f374fa1e9cd"

/-- The Solidity read by `solidity_import`: editing it rebuilds the import. -/
input_dir midnightSol where
  path := "vendor/midnight/src"
  filter := .extension "sol"
  text := true

@[default_target]
lean_lib «Midnight» where
  globs := #[.andSubmodules `Midnight]
  needs := #[midnightSol]
