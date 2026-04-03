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
- REAL root cause (confirmed): `{ upstream = upstream }` in the shim creates a self-referencing RecRecord. Nickel's parser resolves the RHS `upstream` as the record's own field, not the outer let-binding. The RecRecord WHNF evaluation blackholes the record, and field forcing re-enters it → InfiniteRecursion
- Fix: rename shim let-bindings to avoid shadowing: `let _upstream = args.upstream in ... { upstream = _upstream }`
- Same issue affects any `{ fieldname = fieldname }` pattern in generated Nickel source
- Also fixed onix.ncl RecRecord (let-binding prefix trick) for the same class of bug
