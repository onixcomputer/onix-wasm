## Phase 1: onix-modules mkPreamble fix (DONE)

- [x] Change `fun { onix } =>` to `fun onix =>` in all function-style modules
- [x] Change `fun { artifacts, upstream, ... } =>` to `fun args => let ... = args.field in` in evalNickelModule
- [x] Update mkPreamble: `raw_mod onix` instead of `raw_mod { onix = onix }`
- [x] 13/26 eval tests pass (all provider tests pass, all simple module tests pass)

## Phase 2: nickel-plugin WHNF eval for apply_source

- [ ] In `eval_nickel_apply_source`: replace `eval_full_for_export_closure` with `eval_closure` (WHNF)
- [ ] Extend `nickel_to_nix` to handle `Thunk` (borrow closure, recurse into body), `RecRecord` (evaluate fields), `Closurize` (unwrap inner value), `Term::Var` (error with helpful message)
- [ ] Keep `eval_with_cache` using `eval_full_for_export_closure` (string eval has no function closures)
- [ ] Build nickel_plugin.wasm

## Phase 3: Verify

- [ ] Re-run onix-modules eval tests with updated plugin — all 26 should pass
- [ ] Run onix-modules VM tests with updated plugin
