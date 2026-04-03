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
- Root cause: Nickel import resolution creates shared CacheIndex thunks. When onix.ncl is imported, accessing onix.exports triggers the exports.ncl import thunk. If another evaluation path (e.g., merging the consumer result with _lifecycle) also forces through that import chain, the second path hits a blackhole on the still-forcing import thunk
- The validated merge, stdlib thunks, etc. are secondary — the PRIMARY shared state is import thunks in CacheHub
- Confirmed: inlining the helper functions (no imports) works. Importing exports.ncl directly (not through onix.ncl) works. Only the onix.ncl bundle import triggers it
- onix.ncl was a RecRecord (self-referencing fields like Port = contracts.Port). Fixed to use let-bindings. But the import thunk sharing remains
- Best fix: restructure the shim to pass library functions as separate imports rather than bundled through onix.ncl. Or pre-resolve all imports in the shim preamble with individual let-bindings
