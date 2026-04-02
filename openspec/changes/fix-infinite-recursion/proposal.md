## Why

Function-style Nickel modules (`fun { onix } => ...`) crash with
`InfiniteRecursion` when evaluated through the WASM bridge if their impl
accesses deeply nested fields or applies contracts to WASM-bridge arguments.

7 of 14 onix-modules eval tests fail with this error. All failures share
the same root cause. This blocks VM tests and makes the module system
unusable for any service that consumes upstream exports or uses connection
contracts.

## What Changes

The `nickel_plugin` uses `eval_full_for_export_closure` which wraps the
result in `UnaryOp::Force` — a deep, eager evaluation that traverses the
entire closure environment including function parameter record contracts.

When a module is `fun { onix } => body`, Nickel creates a record contract
`{ onix : Dyn }` on the argument. During deep force, the evaluator re-enters
this contract to validate the `onix` field, which triggers re-evaluation of
the library record, which hits the same contract again → infinite recursion.

The fix: replace `eval_full_for_export_closure` with `eval_closure` (WHNF
evaluation) in `eval_with_cache` and `eval_nickel_apply_source`. Then
perform our own recursive walk in `nickel_to_nix`, which already handles
all value types and calls `content_ref()` to force each value individually.
This avoids the blanket deep-force that triggers environment contract
re-evaluation.

## Capabilities

### Modified Capabilities
- `eval_with_cache`: Switch from deep force to WHNF + recursive nickel_to_nix walk
- `eval_nickel_apply_source`: Same change

## Impact

- **Files**: `nickel-plugin/src/lib.rs`
- **APIs**: No API change. Same inputs, same outputs. Only the internal
  evaluation strategy changes.
- **Risk**: Fields that were previously forced by the evaluator now need
  to be forced by `nickel_to_nix`'s `content_ref()`. If `content_ref()`
  doesn't force thunks, we'll get unconverted values. But `content_ref()`
  is documented as forcing to WHNF, so this should work.
