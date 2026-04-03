## Context

Nickel's contract system applies runtime checks derived from type
annotations. The `{ _ : T }` dict type generates a contract that
validates the record argument. When `T = Dyn`, the generated contract
is `$dict_dyn`, a specialized constant-time check.

The evaluation chain that causes recursion:

```
User code: std.record.fields upstream.producer
  -> type annotation: { _ : a } instantiated to { _ : Dyn }
  -> contract: $dict_dyn applied to upstream.producer
  -> $dict_dyn body: %typeof% upstream.producer
  -> %typeof% is a UnaryOp: evaluator pushes continuation, evaluates arg
  -> evaluating arg forces the thunk to WHNF
  -> forcing triggers evaluation through shared CacheHub
  -> evaluation hits std.record.fields on a related record
  -> type annotation: { _ : Dyn } again
  -> $dict_dyn again
  -> %typeof% forces again -> blackhole -> InfiniteRecursion
```

The cycle occurs because all `UnaryOp` dispatch forces the argument to
WHNF before calling the op handler. `%typeof%` receives an already-forced
value. The forcing happens in the eval loop's `Term::Op1` case, which
pushes a continuation and returns the argument for evaluation.

## Goals / Non-Goals

**Goals:**
- Eliminate the forcing in `$dict_dyn` that causes infinite recursion
- Preserve the "is this a record?" check for concrete values
- Maintain correct contract blame for non-records in untyped code
- Minimal, surgical change to nickel-lang-core

**Non-Goals:**
- Changing the type signatures of stdlib record functions
- Modifying the general contract propagation mechanism
- Fixing `$dict_contract` or `$dict_type` (these apply per-field
  contracts, which are meaningful when `T != Dyn`)

## Decision

**Choice:** Add a new `UnaryOp::IsRecord` primop (`%is_record%`) that
inspects the value's term structure without forcing it, then rewrite
`$dict_dyn` to use it instead of `%typeof%`.

**How it works:**

Normal `UnaryOp` dispatch: evaluator pushes continuation, evaluates
argument to WHNF, continuation fires with the WHNF value.

`IsRecord` short-circuits this: the `Term::Op1` case in the evaluator
checks for `IsRecord` and handles it directly by inspecting
`data.arg.content_ref()` without forcing. It returns:

- `true` if the value is a `Record` or `RecRecord` (known record)
- `true` if the value is unevaluated (thunk/var/app/let/etc.) —
  optimistic assumption; the downstream primop validates later
- `false` if the value is a concrete non-record (number, string,
  bool, array, function, etc.)

This preserves the contract check for concrete values (catches
`42 | { _ : Dyn }` with proper blame) while avoiding the forcing
that triggers the cycle for thunked values.

**Implementation:**

1. `src/term/mod.rs`: Add `IsRecord` to `UnaryOp` enum and display
2. `src/eval/mod.rs`: Add short-circuit in `Term::Op1` handler —
   when `op == IsRecord`, inspect `data.arg.content_ref()` directly,
   return a boolean `Closure` without pushing a continuation
3. `stdlib/internals.ncl`: Rewrite `$dict_dyn` to use `%is_record%`
4. Parser: Register `is_record` as a primop name

```rust
// In eval/mod.rs, Term::Op1 handler:
ValueContentRef::Term(Term::Op1(data)) => {
    // Short-circuit for non-forcing ops
    if matches!(data.op, UnaryOp::IsRecord) {
        let is_rec = match data.arg.content_ref() {
            ValueContentRef::Record(_) => true,
            ValueContentRef::Term(Term::RecRecord(..)) => true,
            // Unevaluated: can't tell without forcing. Accept
            // optimistically — downstream ops validate.
            ValueContentRef::Term(
                Term::Var(_) | Term::App(_) | Term::Let(_)
                | Term::Op1(_) | Term::Op2(_) | Term::OpN(_)
                | Term::Annotated(_) | Term::Import(_)
                | Term::Closurize(_)
            ) => true,
            // Concrete non-records: reject
            _ => false,
        };
        Closure {
            value: NickelValue::bool_value(is_rec, pos_idx),
            env,
        }
    } else {
        // Normal unary op dispatch (existing code)
        self.stack.push_op1_cont(...);
        Closure { value: data.arg.clone(), env }
    }
}
```

```nickel
// In stdlib/internals.ncl:
"$dict_dyn" = fun label value =>
    if %is_record% value then
      'Ok value
    else
      'Error { message = "not a record" },
```

**Alternative considered: Make `$dict_dyn` a no-op (`'Ok value`
unconditionally).**

Rejected because it silently accepts non-records. `42 | { _ : Dyn }`
would pass without error, weakening the contract system. The
`%is_record%` approach preserves the check for concrete values.

**Alternative considered: Catch InfiniteRecursion inside `$dict_dyn`.**

Rejected because Nickel has no user-level try/catch. Would require a
new error-recovery primop, which is a larger semantic change than a
non-forcing type check.

**Alternative considered: Change `typ.rs` to not emit `$dict_dyn`.**

Rejected because it changes the Rust contract generation layer for
what is fundamentally a stdlib behavior issue. The `$dict_dyn` contract
is correct — it just needs a non-forcing implementation.

## Risks / Trade-offs

**False positive for thunked non-records:** If a thunk evaluates to a
non-record, `%is_record%` returns `true` (optimistic) and the value
passes `$dict_dyn`. The error surfaces later at the downstream primop
(`%record/fields%` etc.) with a primop error instead of a contract
blame. This is a minor degradation in error reporting for a case that
only occurs in buggy untyped code.

**New primop surface area:** Adding `IsRecord` creates a new internal
primop. It's not intended for user code (prefixed with `%`) but
increases the evaluator's op set by one. The implementation is ~15
lines in the eval loop.

**Maintenance burden:** The `IsRecord` short-circuit in the eval loop
breaks the pattern that all `UnaryOp` are handled uniformly through
the continuation-based dispatch. Future maintainers need to know that
`IsRecord` is special. A comment explaining the rationale is sufficient.
