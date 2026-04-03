## Context

Nickel modules evaluated via the WASM bridge hit `InfiniteRecursion` when
the result references function arguments that were passed through
`Term::App`. The recursion involves `$dict_dyn` — Nickel's internal
dictionary contract that validates record fields.

## Root Cause (fully diagnosed)

The recursion has nothing to do with `std.record.values` specifically,
nor with `eval_full_for_export_closure` vs `eval_closure`. The cause is
in how Nickel's evaluator handles `Term::App(fn, args)`:

1. `eval_nickel_apply_source` builds `Term::App(parsed_fn, args_record)`
   where `args_record` is the Nix arguments converted via `nix_to_nickel`.

2. When Nickel evaluates the `App`, it applies the function's parameter
   contracts to the args record. Even `fun args =>` (no destructuring)
   adds a `Dyn` contract. The contracts become **pending contracts** on
   the args record's fields.

3. The result record closes over these args (e.g., `upstream` is used
   inside the impl). When any stdlib function forces a field from the
   args — `std.record.fields`, `std.record.values`, `std.record.to_array`,
   or even simple field access chains — the pending `$dict_dyn` contract
   fires.

4. `$dict_dyn` recursively validates all fields in the record. For nested
   records (like `upstream.producer.instance.role.machine = exports`),
   this creates a deep evaluation chain that eventually hits the same
   pending contract again through the closure environment → infinite
   recursion.

**Key evidence:** A standalone test with inlined helpers (no imports) and
the SAME data works fine. The same test with imports fails. The import
chain creates shared CacheHub state that changes how pending contracts
propagate through the evaluation environment.

## Approaches Tried

1. **Record pattern removal** (Part A, done): Changed `fun { onix } =>`
   to `fun onix =>` and `fun { artifacts, upstream, .. } =>` to
   `fun args =>`. Eliminated record pattern contracts. Result: 13/26
   tests pass (all non-upstream tests). Upstream tests still fail.

2. **WHNF + per-field forcing**: Replaced `eval_full_for_export_closure`
   with `eval_closure`, added `nickel_to_nix_forcing` that calls
   `vm.eval(field)` for each field. Result: per-field eval still triggers
   $dict_dyn when evaluating fields that reference upstream.

3. **Replace std.record.values with std.record.fields + field access**:
   Rewrote `exports.ncl` to avoid `std.record.values`. Result: `$dict_dyn`
   still fires from `std.record.fields` — the contract is on the args
   record, not specific to `values`.

## Decision (next session)

**Pre-evaluate args before Term::App.** The args record from
`nix_args_to_nickel_record` is a plain `RecordData` with no contracts.
But `Term::App` evaluation attaches contracts from the function's parameter
type. If we pre-evaluate the args via `vm.eval(args)` before building
the `App` term, the args become fully-resolved values that the function
application can't attach new pending contracts to.

Implementation:
```rust
// Pre-evaluate args to strip any lazy structure
let pre_args = VirtualMachine::new(&mut vm_ctxt)
    .eval(args)
    .unwrap();

// Build App with pre-evaluated args
let app = NickelValue::term_posless(Term::App(AppData {
    head: parsed_fn.into(),
    arg: pre_args,
}));

// Now eval_full_for_export_closure can deep-force safely
let value = VirtualMachine::new(&mut vm_ctxt)
    .eval_full_for_export_closure(app.into())
    .unwrap();
```

If pre-evaluation doesn't prevent contract attachment (because Nickel
attaches contracts to the App result, not the args input), the
alternative is:

**Build the source to avoid function application entirely.** Instead of
`eval_nickel_apply_source` building `Term::App(fn, args)`, generate
Nickel source that binds args via `let`:
```
let args = <serialized args> in
<user source applied to args>
```
This requires serializing the args record to Nickel source text, which
`nix_to_nickel_source` already does (though it was deprecated in favor
of ForeignId). For simple args (strings, numbers, plain records), this
works. For ForeignId values (derivations, paths), they need to stay as
ForeignId — so a hybrid approach: serialize data args to source, keep
ForeignId args as Term::App arguments.

## Approaches Tried (Phase 2)

4. **Pre-evaluate args before Term::App**: Called `vm.eval(args)` before
   building the App term. No effect — args are already concrete values,
   and contracts are attached by the function application, not the args.

5. **Manual beta-reduction via Term::Let**: Evaluated source to WHNF,
   extracted Fun(param, body), built `let param = args in body` to
   bypass App entirely. Still fails — `$dict_dyn` comes from the
   IMPORTED Nickel modules, not from function application.

6. **Replace std.record.fields with std.record.to_array in exports.ncl**:
   `std.record.to_array` internally calls `std.record.fields` which
   applies `$dict_dyn`. Same infinite recursion.

## Revised Root Cause

The `$dict_dyn` contract is NOT attached by function application or
arg binding. It's attached by Nickel's standard library. ALL record
introspection functions (`std.record.fields`, `std.record.values`,
`std.record.to_array`) eventually call the typed stdlib wrapper for
`fields` which has the annotation `{_ : Dyn ; r} -> Array String`.
This annotation generates a `$dict_dyn` pending contract on the
record argument.

The raw primop `%record/fields%` doesn't attach contracts, but it's
not available in user Nickel code — only in stdlib internal code.

## Remaining Path: Approach C (patch nickel-lang-core)

Two options within Approach C:

**C1: Remove $dict_dyn from std.record.fields type annotation.**
Change the stdlib's `fields` function to not generate the `{_ : Dyn}`
contract. This is safe because `fields` only reads keys, never
validates field values. Risk: may affect Nickel's contract semantics
for user code that depends on `fields` applying `{_ : Dyn}`.

**C2: Make $dict_dyn skip ForeignId values.** When `$dict_dyn`
validates a record field and encounters a ForeignId, skip validation
(ForeignId is opaque — can't recurse into it). This prevents the
cycle without changing the contract semantics for normal Nickel code.

## Risks

- C1 changes stdlib contract semantics — needs testing
- C2 requires vendored Nickel change that must be maintained across
  Nickel version upgrades
- Both require rebuilding the WASM stdlib cache
