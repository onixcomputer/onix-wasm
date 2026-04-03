# Dict Contract Specification

## Purpose

Defines the behavior of dictionary-type contracts (`{ _ : T }`) in
the Nickel contract system, with focus on the `$dict_dyn` specialization
and the `%is_record%` primop.

## Requirements

### Requirement: Dict contracts validate field types

The `{ _ : T }` contract MUST ensure that every field value in the
record satisfies the contract for type `T`.

When `T` is not `Dyn`, the contract (`$dict_contract` or `$dict_type`)
MUST apply the sub-contract for `T` to each field value.

#### Scenario: Dict contract with concrete type

- GIVEN a record `{ x = 1, y = "hello" }`
- WHEN the contract `{ _ : Number }` is applied
- THEN field `x` passes (1 is a Number)
- AND field `y` fails with a contract blame

### Requirement: Dict Dyn contract is non-forcing

The `{ _ : Dyn }` contract (implemented as `$dict_dyn`) MUST NOT force
its argument to WHNF. It MUST use `%is_record%` to inspect the term
structure without triggering evaluation.

#### Scenario: Dict Dyn on a concrete record

- GIVEN a record value `{ x = 1 }` (already in WHNF)
- WHEN the `$dict_dyn` contract is applied
- THEN `%is_record%` returns `true`
- AND the result is the original record unchanged

#### Scenario: Dict Dyn on a concrete non-record

- GIVEN a number value `42` (concrete, not a thunk)
- WHEN the `$dict_dyn` contract is applied
- THEN `%is_record%` returns `false`
- AND a contract blame error is raised with "not a record"

#### Scenario: Dict Dyn on a thunked record

- GIVEN a thunked record value (not yet evaluated to WHNF)
- WHEN the `$dict_dyn` contract is applied
- THEN `%is_record%` returns `true` (optimistic, value is unevaluated)
- AND the thunk is NOT forced
- AND the value passes through unchanged

#### Scenario: Dict Dyn does not trigger infinite recursion

- GIVEN a record from the WASM bridge that closes over shared CacheHub state
- WHEN `std.record.fields` is called on this record
- THEN the `$dict_dyn` contract applies `%is_record%` without forcing
- AND no infinite recursion occurs
- AND the function returns the field names

### Requirement: IsRecord primop is non-forcing

The `%is_record%` primop MUST NOT force its argument to WHNF. It MUST
inspect the value's term node directly via `content_ref()`.

It MUST return:
- `true` for `Record` values (already evaluated)
- `true` for `RecRecord` terms (recursive records)
- `true` for unevaluated terms (Var, App, Let, Op1, Op2, OpN,
  Annotated, Import, Closurize) — optimistic assumption
- `false` for concrete non-record values (Null, Bool, Number, String,
  Array, Fun, EnumVariant, ForeignId, Label, Type, CustomContract)

#### Scenario: IsRecord on evaluated record

- GIVEN a record `{ a = 1 }`
- WHEN `%is_record%` is applied
- THEN it returns `true`

#### Scenario: IsRecord on number

- GIVEN the number `42`
- WHEN `%is_record%` is applied
- THEN it returns `false`

#### Scenario: IsRecord on thunk

- GIVEN a variable reference that has not been evaluated
- WHEN `%is_record%` is applied
- THEN it returns `true` (optimistic)
- AND the variable is NOT evaluated

### Requirement: Dict contract sub-types still validate

Contracts for `{ _ : T }` where `T` is not `Dyn` MUST continue to
apply the sub-contract to each field. Only the `T = Dyn` case uses
the non-forcing `$dict_dyn`.

#### Scenario: Dict contract with non-Dyn type unchanged

- GIVEN a record `{ x = 1, y = 2 }`
- WHEN the contract `{ _ : Number }` is applied
- THEN `$dict_type` or `$dict_contract` validates each field as before
