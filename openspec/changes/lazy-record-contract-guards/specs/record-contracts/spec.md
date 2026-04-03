# Record Contract Guard Specification

## Purpose

Defines the behavior of record contract shape validation in
`stdlib/internals.ncl` — specifically, when and how the "is this a
record?" check occurs.

## Requirements

### Requirement: Record contracts must not eagerly force arguments

Record contract functions (`$record_contract`, `$record_type`,
`$dict_contract`, `$dict_type`, `$dict_dyn`) MUST NOT call `%typeof%`
or any other forcing operation on their `value` argument before
delegating to the inner record primop.

The record shape check MUST be performed by the inner primop
(`%record/merge_contract%`, `%record/split_pair%`,
`%contract/record_lazy_apply%`, `%record/map%`) as part of its
normal operation.

#### Scenario: Contract on a thunked record

- GIVEN a thunked record value whose evaluation shares CacheHub state
  with the caller's evaluation
- WHEN a record contract is applied
- THEN the contract does not force the thunk for shape checking
- AND no spurious InfiniteRecursion occurs
- AND the inner primop forces the value when it operates on the record

#### Scenario: Contract on a concrete record

- GIVEN an already-evaluated record `{ x = 1 }`
- WHEN a record contract is applied
- THEN the contract delegates to the inner primop
- AND the inner primop operates on the record normally

#### Scenario: Contract on a non-record

- GIVEN a non-record value (e.g., a number)
- WHEN a record contract is applied
- THEN the inner primop raises a type error
- AND the error identifies the expected type (Record) and actual type

### Requirement: Dict Dyn contract is identity

The `$dict_dyn` contract (`{ _ : Dyn }`) MUST return `'Ok value`
unconditionally. Since `Dyn` is satisfied by every value, the only
check `$dict_dyn` performed was the `%typeof%` record guard, which
is now removed.

#### Scenario: Dict Dyn passes any value

- GIVEN any value
- WHEN the `$dict_dyn` contract is applied
- THEN the result is `'Ok value`

### Requirement: Per-field contracts still apply

For `$dict_contract`, `$dict_type`, `$record_contract`, and
`$record_type`, the per-field contract logic (lazy application via
`%contract/record_lazy_apply%`, direct application via `%record/map%`,
or merge via `%record/merge_contract%`) MUST still execute when the
inner primop processes the record.

#### Scenario: Dict contract with concrete type still validates fields

- GIVEN a record `{ x = 1, y = "hello" }`
- WHEN `{ _ : Number }` contract is applied (via `$dict_type`)
- THEN field `x` passes
- AND field `y` fails with a contract blame error

### Requirement: Inner primops reject non-records

The record primops (`%record/merge_contract%`, `%record/split_pair%`,
`%contract/record_lazy_apply%`, `%record/map%`, `%record/fields%`)
MUST reject non-record arguments with a type error.

#### Scenario: Primop receives non-record

- GIVEN a non-record value passed to `%record/map%`
- WHEN the primop evaluates
- THEN it raises an evaluation error with "expected Record"
