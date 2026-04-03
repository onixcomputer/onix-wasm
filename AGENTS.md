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

## Infinite Recursion Bug (active)
- $dict_dyn contract on records causes infinite recursion when Nickel stdlib record introspection functions operate on records from the WASM bridge
- Root cause is in the pre-compiled Nickel stdlib, not in function application or user code
- All approaches tried so far (pre-eval args, Let instead of App, patching to_array type, rewriting exports.ncl) don't work
- The $dict_dyn is propagated through the stdlib's internal record namespace field access pattern
- Next: need to understand how the stdlib record module exports carry $dict_dyn and either patch the evaluator or restructure the Nickel module pipeline
