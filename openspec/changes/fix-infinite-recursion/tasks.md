## Phase 1: onix-modules mkPreamble fix (DONE)

- [x] Change `fun { onix } =>` to `fun onix =>` in all function-style modules
- [x] Change `fun { artifacts, upstream, ... } =>` to `fun args => let ... = args.field in` in evalNickelModule
- [x] Update mkPreamble: `raw_mod onix` instead of `raw_mod { onix = onix }`
- [x] Replace `std.record.values` with `std.record.fields` + field access in `exports.ncl` (didn't help but cleaner)
- [x] 13/26 eval tests pass (all provider + simple module tests pass)

## Phase 2: Fix $dict_dyn recursion on function args

Remaining 13 tests all fail with `$dict_dyn` infinite recursion when
the result references `upstream` args that were passed through `Term::App`.

Try in order:

- [ ] **Approach A: Pre-evaluate args.** Call `vm.eval(args)` before building `Term::App`. If args are fully-resolved values, function application shouldn't attach pending contracts. Build plugin, test consumer module.
- [ ] **Approach B: Avoid Term::App for args with nested records.** Serialize data-only args (upstream, artifacts) to Nickel source text via `nix_to_nickel_source`. Keep ForeignId args (packages) as `Term::App` arguments. This is a hybrid: source text for data, function application for opaque handles.
- [ ] **Approach C: Patch nickel-lang-core.** Add a `frozen` flag to args records that prevents `$dict_dyn` from attaching. Set it in `nix_to_nickel` for all bridge-produced records. Requires vendored Nickel change.

## Phase 3: Verify

- [ ] Build nickel_plugin.wasm with the fix
- [ ] Re-run all 26 onix-modules eval tests — should all pass
- [ ] Run VM tests (vm-greeting-default, vm-upstream-wiring, vm-static-server, vm-e2e-smoke)
- [ ] Push onix-wasm changes, update onix-modules flake.lock
