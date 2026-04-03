## Phase 1: Add IsRecord primop

- [ ] Add `IsRecord` variant to `UnaryOp` enum in `src/term/mod.rs`
- [ ] Add display impl: `IsRecord => write!(f, "is_record")`
- [ ] Add arity (1) to the arity method
- [ ] Register `is_record` in the primop parser (same file or parser module where other primops are registered)
- [ ] Add short-circuit handling in `src/eval/mod.rs` `Term::Op1` case: when `op == IsRecord`, inspect `data.arg.content_ref()` directly, return Bool closure without pushing a continuation
- [ ] Add `IsRecord` case to `src/eval/operation.rs` `eval_op1` (unreachable — the short-circuit in mod.rs means it never reaches eval_op1, but match exhaustiveness requires it)
- [ ] Add to AST compat layer (`src/ast/compat.rs`) if required for AST<->Term conversion

## Phase 2: Update $dict_dyn

- [ ] Change `$dict_dyn` in `stdlib/internals.ncl` from `%typeof%` to `%is_record%`
- [ ] Add `IsRecord` to any typecheck stubs in `src/typecheck/operation.rs` if needed for completeness

## Phase 3: Test in nickel-lang-core

- [ ] Run existing integration tests — no regressions expected
- [ ] Verify the `dictionary` test in `contracts_fail.rs` still passes (uses `{ _ | String }` which is `$dict_contract`, not `$dict_dyn`)
- [ ] Add a test: `42 | { _ : Dyn }` applied to a concrete non-record still produces contract blame
- [ ] Add a test: `{ a = 1 } | { _ : Dyn }` passes

## Phase 4: Rebuild and test WASM plugin

- [ ] Apply the vendor changes to the local `vendor/nickel-lang-core` directory
- [ ] Rebuild onix-wasm (`nix build`)
- [ ] Run all 26 onix-modules eval tests with the patched WASM binary
- [ ] Verify previously-passing 13 tests still pass
- [ ] Verify previously-failing 13 upstream/consumer tests now pass

## Phase 5: Upstream

- [ ] Port changes to nickel-wasm-vendor repo (brittonr/nickel-wasm, wasm-vendor branch)
- [ ] Update onix-wasm flake.lock to point at the new vendor commit
- [ ] Remove the local vendor patches from default.nix (if any remain)
- [ ] Verify `nix build` succeeds from clean flake
