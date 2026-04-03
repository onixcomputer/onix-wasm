## Phase 1: Patch internals.ncl

- [ ] Remove `%typeof%` guard from `$record_contract` (line 218) — wrap body in `'Ok (...)`
- [ ] Remove `%typeof%` guard from `$record_type` (line 236) — remove if/else, keep body
- [ ] Remove `%typeof%` guard from `$dict_contract` (line 282) — remove if/else, keep `'Ok` body
- [ ] Remove `%typeof%` guard from `$dict_type` (line 297) — remove if/else, keep `'Ok` body
- [ ] Remove `%typeof%` guard from `$dict_dyn` (line 312) — replace body with `'Ok value`

## Phase 2: Test in nickel-lang-core

- [ ] Run existing integration tests in the vendored nickel-lang-core
- [ ] Identify tests that assert contract blame for non-record arguments
- [ ] Update those tests to expect primop type errors instead
- [ ] Add test: record contract on a record passes
- [ ] Add test: dict contract with concrete type still validates fields

## Phase 3: Build and test WASM plugin

- [ ] Wire the patch into `default.nix` postUnpack (sed on vendored stdlib)
- [ ] Build onix-wasm with `nix build`
- [ ] Run all 26 onix-modules eval tests with patched WASM binary
- [ ] Verify all 13 previously-passing tests still pass
- [ ] Verify all 13 previously-failing upstream/consumer tests now pass

## Phase 4: Upstream the vendor patch

- [ ] Port internals.ncl changes to nickel-wasm-vendor repo
- [ ] Update onix-wasm flake.lock to new vendor commit
- [ ] Remove sed patches from default.nix
- [ ] Verify clean `nix build` from flake
