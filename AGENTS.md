# Agent Notes

## Build
- WASM target: `nix build` (builds all plugins via default.nix)
- Dev check: `nix develop --command bash -c 'cargo check --target wasm32-unknown-unknown -p nickel-plugin'`
- If rustup ld wrappers are stale: `rustup toolchain install stable --force`
- Vendor dir comes from `nickel-wasm-vendor` flake input, set up in `default.nix` `postUnpack`

## Testing
- Need onix nix fork (onixcomputer/nix at /home/brittonr/git/nix) for `builtins.wasm` + string context ABI
- Onix nix binary: `/nix/store/8rlz2v16wxv1xqxad800wjvgpj9gvdl5-nix-2.33.3/bin/nix`
- System nix has `builtins.wasm` but NOT `env::has_context` host import
- Run eval tests: `$NIX_ONIX eval --impure --expr '...' --extra-experimental-features 'nix-command wasm-builtin'`

## Architecture
- `nix-wasm-rust/`: Rust bindings for the nix WASM host ABI (Value type, get_type, make_string, etc.)
- `nickel-plugin/src/lib.rs`: Nickel evaluator WASM plugin — evalNickel, evalNickelFile, evalNickelWith, evalNickelFileWith
- `vendor/nickel-lang-core/`: Vendored Nickel evaluator (from nickel-wasm-vendor flake input)
- `nix/wasm.nix`: Nix wrappers that call builtins.wasm with the plugin paths

## Infinite Recursion Bug (FIXED)
- Root cause: five record contract functions in `stdlib/internals.ncl` eagerly force args via `%typeof% value == 'Record` before delegating to inner primops
- `%typeof%` is a UnaryOp that forces to WHNF → hits shared CacheHub thunks → blackhole → spurious InfiniteRecursion
- Fix: removed `%typeof%` guards from `$record_contract`, `$record_type`, `$dict_contract`, `$dict_type`, `$dict_dyn`
- Each inner primop already validates record shape via `mk_type_error!("Record")`
- `$dict_dyn` became identity: `fun label value => 'Ok value`
- The old `std.ncl` sed workaround (stripping `forall a. { _ : a }` type annotations) is no longer needed
- Patch lives in nickel-wasm-vendor (../nickel-wasm, branch wasm-vendor)
- CRITICAL: $record_contract must NOT wrap in 'Ok — %record/merge_contract% already wraps via MergeMode::Contract
- To run integration tests: `cd ../nickel-wasm && nix shell nixpkgs#gcc -c bash -c 'PATH="$HOME/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/bin:$PATH" cargo test -p nickel-lang-core --test integration'`
- dev-dependencies in nickel-wasm core/Cargo.toml are stripped by default.nix postUnpack (nickel-lang-utils not vendored)
- Also fixed: $array and $array_dyn had same %typeof% guard issue — removed in same pattern
- Remaining onix-modules failures (16/35): NOT from %typeof% guards, NOT from merge_contract directly
- Root cause: the shim does `validated = mod.interface.roles.X & user_settings` (merge with contracts) in the SAME evaluation as `mod.impl { settings = validated, upstream = ..., ... }`. The merge attaches pending contracts from the interface to `validated`. When `impl` forces those contracts while also forcing through stdlib helpers (exports.first_result etc.), both paths hit the same CacheHub thunks → blackhole
- Confirmed: simplified reproduction without the `validated` merge works fine
- Best fix: split settings validation into a separate WASM call. Serialize validated settings back to Nix, then pass as plain literal args to the impl call. This isolates CacheHub state between the two evaluation phases
- Alternative: pre-force validated settings to Nix within the same WASM call before passing to impl (using nickel_to_nix round-trip)
