# Piglog 2: Testing

## Running the Test Suite

From the repository root:

```bash
swipl -t halt -g "
  use_module(library(plunit)),
  use_module(piglog2),
  use_module(piglog2_safety),
  use_module(piglog2_analyser),
  use_module(piglog2_estimator),
  use_module(piglog2_transformer),
  consult('tests/test_basic'),
  consult('tests/test_analysis'),
  consult('tests/test_safety'),
  consult('tests/test_estimation'),
  consult('tests/test_transform'),
  consult('tests/test_repl'),
  consult('tests/test_generated'),
  run_tests"
```

Using the test runner:

```bash
swipl -t halt -g "run_all_tests" tests/run_tests.pl
```

## Test Files

| File | Description |
|------|-------------|
| `tests/test_basic.pl` | Basic conversion: independent → concurrent, dependent → sequential, cuts, short predicates |
| `tests/test_analysis.pl` | Conjunction flattening, variable flow, section independence |
| `tests/test_safety.pl` | Thread-safety classification, user declarations, effectful predicates |
| `tests/test_estimation.pl` | Cost declarations, thresholds, static estimates |
| `tests/test_transform.pl` | Transformer output structure, maplist conversion, no-scheduler check |
| `tests/test_repl.pl` | REPL commands: `piglog_output`, `piglog_convert`, `piglog_write`, `piglog_report` |
| `tests/test_generated.pl` | Generated code correctness: loads, uses `concurrent/3`, no heuristics |

## Test Categories

### Basic Conversion Tests (`test_basic`)

- `two_independent_long_concurrent`: Two expensive, independent sections → `concurrent/3`
- `three_independent_long_concurrent`: Three independent sections → single `concurrent/3` call
- `dependent_predicates_sequential`: Chain a→b→c (transitive dependencies) → stays sequential
- `short_independent_sequential`: Cheap predicates → stays sequential (threshold not met)
- `mixed_long_short_only_long_converted`: Only expensive sections grouped, cheap sections remain sequential
- `independent_chains_concurrent`: Load→Process chain + independent Fetch → correct grouping
- `cut_as_boundary`: Cut between sections prevents concurrent grouping
- `ite_not_concurrent`: If-then-else remains sequential

### Analysis Tests (`test_analysis`)

- `flatten_simple_conjunction`: `(a, b, c)` → `[a, b, c]`
- `flatten_nested_conjunction`: `((a, b), c)` → `[a, b, c]`
- `build_sections_basic`: Variable flow per section
- `find_independent_groups_basic`: Groups of independent sections found
- `find_no_groups_sequential`: Chain has no independent groups

### Safety Tests (`test_safety`)

- `known_safe_predicates`: `is/2`, `=/2`, `atom/1` etc. are thread-safe
- `known_unsafe_predicates`: `assert/1`, `format/1` etc. are thread-unsafe
- `user_declarations_override`: `piglog_thread_safe/1` overrides static classification
- `section_safety_check`: Section with unsafe goal → not safe for concurrency

### Estimation Tests (`test_estimation`)

- `user_cost_declaration`: `:- piglog_cost(pred/2, 50.0)` gives Cost = 50.0
- `long_declaration_exceeds_threshold`: `:- piglog_long(pred/2)` → threshold exceeded
- `short_predicate_under_threshold`: Unknown pred → low static cost → threshold not exceeded
- `calibration_round_trip`: Store and retrieve calibration data

### Transformer Tests (`test_transform`)

- `two_independent_produces_concurrent`: Output structure matches `concurrent(N, [...], [])`
- `sequential_continuation_preserved`: Continuation after concurrent group stays sequential
- `maplist_no_transform_when_short`: Short maplist predicate stays as `maplist/3`
- `no_piglog_scheduler_in_output`: Generated clause body contains no scheduler calls
- `transform_terms_converts_clauses`: Full pipeline via `transform_terms/3`
- `transform_terms_preserves_facts`: Facts pass through unchanged
- `transform_terms_preserves_directives`: `:- use_module(...)` directives preserved

### REPL Tests (`test_repl`)

- `piglog_output_from_terms`: Terms printed to stdout
- `piglog_convert_returns_terms`: `piglog_convert/3` returns term list
- `piglog_write_to_file`: Output written to temp file
- `piglog_report_runs`: Report header printed
- `piglog_output_file`: Convert from a `.pl` file
- `piglog_output_action`: `piglog(Source, output)` interface works
- `set_and_get_config`: Config round-trip

### Generated Code Tests (`test_generated`)

- `generated_code_loads`: Converted terms form a valid list
- `no_scheduler_in_generated`: No `piglog_schedule/piglog_runtime` calls in output
- `sequential_preserved`: Dependent chain preserved exactly
- `no_profitability_heuristics`: No runtime heuristic predicates in output

## Writing New Tests

Use SWI-Prolog's `plunit` framework:

```prolog
:- begin_tests(my_tests).

test(my_test) :-
    declare_long(my_pred/2),
    declare_thread_safe(my_pred/2),
    Clause = (p(X, A, B) :- my_pred(X, A), my_pred(X, B)),
    transform_clause(Clause, [], Generated, _, Report),
    report_is_converted(Report),
    Generated = (p(_, _, _) :- concurrent(_, _, [])).

:- end_tests(my_tests).
```

Helper predicates available at module level in test files:
- `declare_long(Pred/Arity)` — add user long declaration
- `declare_thread_safe(Pred/Arity)` — add user thread-safe declaration
- `report_is_converted(Report)` — check that a report indicates conversion
- `report_is_sequential(Report)` — check that a report indicates sequential retention
