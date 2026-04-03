## Why

The `$dict_dyn` contract causes infinite recursion when Nickel stdlib
record introspection functions (`std.record.fields`, `std.record.values`,
`std.record.to_array`, etc.) operate on records from the WASM embedding
bridge.

These functions carry the type annotation `forall a. { _ : a } -> ...`.
When instantiated, `{ _ : a }` becomes `{ _ : Dyn }`, which generates
`$dict_dyn` as a contract on the function argument. `$dict_dyn` uses
`%typeof%` to verify the argument is a record. `%typeof%` is a standard
`UnaryOp` — the evaluator forces the argument to WHNF before the op
handler runs. For records that close over shared evaluator state (the
`CacheHub` in the WASM embedding), this forcing triggers re-evaluation
of thunks that eventually call back into `std.record.fields` on the
same record, producing `InfiniteRecursion`.

7 of 14 downstream tests fail with this error. All failures involve
modules that call `std.record.fields` or `std.record.to_array` on
records passed from the host via the WASM bridge.

## What Changes

Add a new `UnaryOp::IsRecord` primop that checks whether a value is a
record WITHOUT forcing it to WHNF. Unlike all other `UnaryOp` variants,
`IsRecord` short-circuits the evaluator's continuation-based dispatch
and inspects the value's term structure directly.

For concrete values (Record, Number, String, etc.), it returns a
definitive answer. For unevaluated thunks, it returns `true`
(optimistic — the downstream primop validates when the value is
actually used).

Rewrite `$dict_dyn` in `internals.ncl` to use `%is_record%` instead
of `%typeof%`.

## Capabilities

### Modified Capabilities
- `dict-dyn-contract`: `$dict_dyn` no longer forces its argument to
  WHNF. Concrete non-records are still rejected with contract blame.
  Thunked values pass through and are validated by the consuming primop.

### New Capabilities
- `is-record-primop`: Non-forcing record type check via `%is_record%`.
  Internal primop, not exposed to user code.

## Impact

- **Files**: `src/term/mod.rs`, `src/eval/mod.rs`, `stdlib/internals.ncl`,
  parser (primop name registration)
- **APIs**: No user-facing API change
- **Behavioral change**: Thunked non-records passed through `{ _ : Dyn }`
  get a primop error instead of a contract blame error. Concrete
  non-records still get contract blame as before.
- **Testing**: Existing tests should pass. May need to add a test for
  `%is_record%` on various value types.
