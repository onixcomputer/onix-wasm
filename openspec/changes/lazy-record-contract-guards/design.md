## Context

Nickel's standard library defines five internal contract functions for
record types. Each one guards its body with `if %typeof% value == 'Record`.

`%typeof%` is a `UnaryOp`. All `UnaryOp` dispatch forces the argument
to WHNF before the op handler runs — this happens in the eval loop's
`Term::Op1` case, which pushes a continuation and returns the argument
for evaluation.

For a concrete value (a record literal already in memory), this is
instant. For a thunk (a suspended computation), forcing evaluates the
thunk. If that evaluation passes through shared CacheHub entries —
stdlib imports, helper modules shared across callers — it can re-enter
a thunk that is already being forced higher up the stack. The evaluator
detects this (blackhole) and raises `InfiniteRecursion`.

The cycle that triggers it:

```
consumer module: data | ProducerExport
  -> $record_contract fires
  -> %typeof% value forces `first_result upstream.producer`
  -> first_result calls std.record.fields
  -> std.record.fields type: { _ : a } generates $dict_dyn
  -> $dict_dyn: %typeof% forces the nested record
  -> forcing passes through shared stdlib thunks
  -> hits a thunk being forced from step 2
  -> blackhole -> InfiniteRecursion
```

The data (`upstream.producer`) is a tree — producer evaluates before
consumer, results flow one way. The cycle is purely in the evaluation
graph from forcing through shared imports.

## Goals / Non-Goals

**Goals:**
- Eliminate spurious InfiniteRecursion from record contracts
- Fix all five contract functions, not just `$dict_dyn`
- Preserve record contract semantics for well-typed programs
- Stdlib-only change — no evaluator modifications

**Non-Goals:**
- Changing the evaluator's `UnaryOp` forcing behavior
- Adding new primops
- Modifying contract application or pending contract propagation
- Changing stdlib function type signatures

## Decision

**Choice:** Remove the `%typeof%` guard from all five record contract
functions. Let the inner primop validate the record shape.

Each contract's body already calls a record primop that checks its
argument. The primop raises `mk_type_error!("Record")` for non-records.
The `%typeof%` guard is a duplicate check that fires earlier.

The change per function:

**`$record_contract`** (line 218):
```nickel
# Before:
"$record_contract" = fun record_contract =>
    fun label value =>
      if %typeof% value == 'Record then
        %record/merge_contract% label value record_contract
      else
        'Error { message = "expected a Record" },

# After:
"$record_contract" = fun record_contract =>
    fun label value =>
      %record/merge_contract% label value record_contract,
```

**`$record_type`** (line 236):
```nickel
# Before:
fun label value =>
  if %typeof% value == 'Record then
    let split_result = %record/split_pair% field_contracts value in
    ...
  else
    'Error { message = "expected a record" },

# After:
fun label value =>
  let split_result = %record/split_pair% field_contracts value in
  ...
  # (remove the else branch entirely)
```

**`$dict_contract`** (line 282):
```nickel
# Before:
"$dict_contract" = fun Contract =>
    fun label value =>
      if %typeof% value == 'Record then
        'Ok (%contract/record_lazy_apply% ...)
      else
        'Error { message = "not a record" },

# After:
"$dict_contract" = fun Contract =>
    fun label value =>
      'Ok (%contract/record_lazy_apply% ...),
```

**`$dict_type`** (line 297):
```nickel
# Before:
"$dict_type" = fun Contract =>
    fun label value =>
      if %typeof% value == 'Record then
        'Ok (%record/map% value ...)
      else
        'Error { message = "not a record" },

# After:
"$dict_type" = fun Contract =>
    fun label value =>
      'Ok (%record/map% value ...),
```

**`$dict_dyn`** (line 312):
```nickel
# Before:
"$dict_dyn" = fun label value =>
    if %typeof% value == 'Record then
      'Ok value
    else
      'Error { message = "not a record" },

# After:
"$dict_dyn" = fun label value => 'Ok value,
```

**Rationale:** The guard exists to produce a contract blame error
with "expected a record" / "not a record" for non-record values. With
the guard removed, non-records hit the inner primop's type check
instead. The primop error is equally clear ("expected Record, got
Number") but lacks the contract blame label chain.

This tradeoff is acceptable because:

1. In typed Nickel code, the type checker catches record mismatches
   statically. The runtime contract only fires in untyped code.
2. The primop error identifies the same problem — wrong type at the
   same position.
3. The guard causes a real, blocking bug (spurious InfiniteRecursion)
   in any system that passes records through stdlib functions with
   shared imports.

**Alternative considered:** Add a non-forcing `%is_record%` primop.

Rejected because implementing it correctly requires resolving
variables through the closure environment and inspecting thunk state
without forcing — significant evaluator complexity. And for the actual
bug (thunked records), it returns `true` optimistically, producing
identical behavior to removing the guard.

**Alternative considered:** Catch `InfiniteRecursion` inside the
guard and return `'Ok value`.

Rejected because Nickel has no user-level error recovery. Would
require a new primop or eval loop change, larger than the fix.

## Risks / Trade-offs

**Error message degradation:**
Before: contract blame with "expected a Record", includes label path.
After: primop error "expected Record, got X", no label path.
The failure is caught at the same position. The message is less
structured but equally informative for debugging.

**Semantic weakening of `$dict_dyn`:**
`$dict_dyn` becomes a complete no-op (`'Ok value`). The `{ _ : Dyn }`
contract no longer rejects non-records. In practice, `{ _ : Dyn }`
almost exclusively comes from stdlib type annotations like
`forall a. { _ : a } -> ...` instantiated with `a = Dyn`. These
always receive records.

**Upstream divergence:**
The vendored patch diverges from upstream nickel-lang-core. If
upstream changes `internals.ncl`, the patch needs re-applying on
vendor updates.
