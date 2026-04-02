## Context

`eval_full_for_export_closure` wraps the result term in `UnaryOp::Force`
which deep-evaluates the entire term tree including all pending contracts
in the closure environment. For function-style modules, this means
evaluating the record contract on `fun { onix } =>` which recurses
through the library's re-exports.

The `nickel_to_nix` function already does its own recursive walk via
`content_ref()` dispatch, forcing each value to WHNF individually. The
deep `Force` is redundant — it forces everything eagerly before
`nickel_to_nix` even starts, and that's where the recursion happens.

## Decision

Two-part fix:

**Part A (onix-modules mkPreamble):** Change module convention from
`fun { onix } =>` to `fun onix =>` and outer wrapper from
`fun { artifacts, upstream, ... } =>` to `fun args => let upstream = args.upstream in ...`.
This eliminates record pattern contracts on function parameters. Done.

**Part B (nickel-plugin eval strategy):** Replace `eval_full_for_export_closure`
with `eval_closure` (WHNF) in `eval_nickel_apply_source`. Then extend
`nickel_to_nix` to handle `Thunk`, `RecRecord`, and `Closurize` variants
by recursing into them. `eval_with_cache` (string eval, no function
application) can keep using `eval_full_for_export_closure` since it has
no function closure to recurse into.

The WHNF approach is needed because `std.record.values` (used by
`exports.ncl`'s `first_result` helper) applies an internal `$dict_dyn`
contract. Deep force traverses through this contract into the upstream
record, which is a Nix-bridge value, causing infinite recursion.

Key: `content_ref()` on a `NickelValue` forces the value to WHNF (head
normal form), which resolves thunks, applies pending contracts for that
specific field, and returns a `ValueContentRef` variant. This is sufficient
for `nickel_to_nix` to dispatch on the type and recurse into records/arrays.

The `subst` call in `eval_full_for_export_closure` (which substitutes free
variables for export) is not needed because `nickel_to_nix` never inspects
variable names — it only looks at fully-evaluated values via `content_ref()`.

## Risks

- If a Nickel expression returns a lazy thunk at the top level (not a value),
  `eval_closure` might not force it far enough for `nickel_to_nix` to see
  a concrete type. Mitigation: `eval_closure` evaluates to WHNF which should
  reveal the outermost constructor (Record, Array, String, etc.).
- `not_exported` fields: `eval_full_for_export_closure` passed
  `ignore_not_exported: true` to skip them during force. With the new
  approach, `nickel_to_nix` calls `iter_serializable()` which already
  skips `not_exported` fields. No behavior change.
