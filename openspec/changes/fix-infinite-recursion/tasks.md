## Phase 1: onix-modules mkPreamble fix (DONE)

- [x] Change `fun { onix } =>` to `fun onix =>` in all function-style modules
- [x] Change `fun { artifacts, upstream, ... } =>` to `fun args => let ... = args.field in` in evalNickelModule
- [x] Update mkPreamble: `raw_mod onix` instead of `raw_mod { onix = onix }`
- [x] Replace `std.record.values` with `std.record.fields` + field access in `exports.ncl` (didn't help but cleaner)
- [x] 13/26 eval tests pass (all provider + simple module tests pass)

## Phase 2: Fix $dict_dyn recursion on function args

Remaining 13 tests all fail with `$dict_dyn` infinite recursion when
the result references `upstream` args passed through the WASM bridge.

Ruled out (tested, no effect on $dict_dyn):

- [x] **Approach A: Pre-evaluate args.** No effect — args are already concrete, contracts come from stdlib not args.
- [x] **Approach A': Manual beta-reduction (Let instead of App).** No effect — $dict_dyn comes from imported module code, not function application.
- [x] **Replace std.record.fields/to_array in exports.ncl.** `to_array` internally calls `fields` which applies $dict_dyn. All stdlib record introspection funnels through the same typed wrapper.

Next:

- [ ] **Approach C: Patch nickel-lang-core.** Strip the `{_ : Dyn}` type annotation from `std.record.fields` and `std.record.to_array` in the vendored stdlib, OR make `$dict_dyn` skip ForeignId values. Requires patching `vendor/nickel-lang-core`.

## Phase 3: Verify

- [ ] Build nickel_plugin.wasm with the fix
- [ ] Re-run all 26 onix-modules eval tests — should all pass
- [ ] Run VM tests (vm-greeting-default, vm-upstream-wiring, vm-static-server, vm-e2e-smoke)
- [ ] Push onix-wasm changes, update onix-modules flake.lock
