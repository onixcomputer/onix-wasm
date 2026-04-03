## Why

Five record contract functions in `stdlib/internals.ncl` eagerly force
their argument via `%typeof% value == 'Record` before doing any work.
This causes spurious `InfiniteRecursion` when the forced value shares
evaluator cache state with the contract's own evaluation — a situation
that arises whenever modules pass records through stdlib functions in
the presence of shared imports.

The recursion is spurious: the data is tree-shaped, not circular. The
cycle exists only in the evaluation graph because `%typeof%` forces a
thunk whose evaluation chain passes through shared CacheHub entries
(stdlib imports, helper modules) that are already being evaluated
higher up the stack.

This blocks any system that evaluates Nickel modules with upstream
wiring — whether driven from a WASM bridge, the Rust API, or a pure
Nickel module evaluator. The organist project hit the same class of
bug (nickel-lang/nickel#1630), which was closed without root cause
analysis when an unrelated change happened to break the specific cycle.

The `%typeof%` guard is redundant in every case. Each contract's inner
operation (`%record/merge_contract%`, `%record/split_pair%`,
`%record/map%`, `%contract/record_lazy_apply%`, `%record/fields%`)
already rejects non-records with `mk_type_error!("Record")`.

## What Changes

Remove the `if %typeof% value == 'Record then ... else 'Error`
guard from all five record contract functions in `internals.ncl`:

| Contract | Line | Inner operation |
|---|---|---|
| `$record_contract` | 218 | `%record/merge_contract%` |
| `$record_type` | 236 | `%record/split_pair%` |
| `$dict_contract` | 282 | `%contract/record_lazy_apply%` |
| `$dict_type` | 297 | `%record/map%` |
| `$dict_dyn` | 312 | none (returns value as-is) |

For `$dict_dyn` specifically, the entire function body becomes
`'Ok value` — the guard was the only logic.

For the other four, the guard is removed and the body proceeds
directly to the inner primop, which forces the value as part of its
own operation. Non-records hit the primop's type check instead of
the contract's `%typeof%` guard.

## Capabilities

### Modified Capabilities
- `record-contract-guards`: Record contracts no longer eagerly force
  their argument for the shape check. The shape is validated by the
  inner primop when it actually operates on the value.

## Impact

- **Files**: `stdlib/internals.ncl` (5 functions, ~10 lines changed)
- **APIs**: No change to Nickel's public API or stdlib function signatures
- **Error behavior**: Non-record values passed to record-typed positions
  get a primop type error instead of a contract blame error. The error
  identifies the same problem but lacks contract blame path tracking.
  This only affects untyped code — typed code catches the mismatch
  statically.
- **Testing**: Any test that asserts contract blame (not primop error)
  for non-records passed through record contracts needs updating.
- **Upstream**: Patch the nickel-wasm-vendor repo and update flake.lock.
