## Phase 1: Patch internals.ncl

- [x] Remove `%typeof%` guard from `$record_contract` (line 218) — wrap body in `'Ok (...)`
- [x] Remove `%typeof%` guard from `$record_type` (line 236) — remove if/else, keep body
- [x] Remove `%typeof%` guard from `$dict_contract` (line 282) — remove if/else, keep `'Ok` body
- [x] Remove `%typeof%` guard from `$dict_type` (line 297) — remove if/else, keep `'Ok` body
- [x] Remove `%typeof%` guard from `$dict_dyn` (line 312) — replace body with `'Ok value`

## Phase 2: Test in nickel-lang-core

- [ ] Run existing integration tests in the vendored nickel-lang-core
- [ ] Identify tests that assert contract blame for non-record arguments
- [ ] Update those tests to expect primop type errors instead
- [x] Add test: record contract on a record passes
- [x] Add test: dict contract with concrete type still validates fields

## Phase 3: Build and test WASM plugin

- [x] Commit patch to nickel-wasm-vendor repo (../nickel-wasm)
- [x] Update onix-wasm flake.lock to new vendor commit
- [x] Build onix-wasm with `nix build`
- [x] Test std.record.to_array, fields, values, map on bridge data — all pass
- [x] Test evalNickelWith with record merge, dict type, record type — all pass
- [x] Test nested record introspection and evalNickelFileWith — all pass
- [x] Remove old `std.ncl` sed workaround from default.nix — no longer needed
- [x] Rebuild and retest without sed workaround — all pass

## Phase 4: Upstream the vendor patch

- [x] Port internals.ncl changes to nickel-wasm-vendor repo
- [x] Update onix-wasm flake.lock to new vendor commit
- [x] Remove sed patches from default.nix
- [x] Verify clean `nix build` from flake
