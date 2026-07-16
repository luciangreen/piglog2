# Piglog 2: Architecture

## Module Overview

```
piglog2.pl
  ├── piglog2_reader.pl     -- source loading
  ├── piglog2_analyser.pl   -- clause analysis
  ├── piglog2_safety.pl     -- thread-safety classification
  ├── piglog2_estimator.pl  -- cost estimation
  ├── piglog2_transformer.pl -- source-to-source transform
  ├── piglog2_printer.pl    -- output formatting
  ├── piglog2_loader.pl     -- load generated code into module
  ├── piglog2_report.pl     -- conversion reports
  ├── piglog2_calibrate.pl  -- overhead calibration
  ├── piglog2_runtime.pl    -- helpers for generated code
  └── piglog2_config.pl     -- configuration
```

## Conversion Pipeline

```
Source
  │
  ▼ read_source/2 (piglog2_reader)
Terms (list of clause terms)
  │
  ▼ transform_terms/3 (piglog2_transformer)
  │  For each clause:
  │    analyse_clause/3 (piglog2_analyser)
  │      flatten_conjunction → Goals list
  │      build_sections → section/4 list
  │      find_independent_groups → index groups
  │    transform_clause/5 (piglog2_transformer)
  │      section_pair_independent (pairwise + transitive dependency check)
  │      build_cliques_from_pairs → maximal cliques
  │      find_best_index_set → filter by cost threshold & safety
  │      apply_transformation → concurrent/3 body
  │      rebuild_body_sequential → non-concurrent sections sequential
  ▼
transform_result(Generated, Helpers, Reports)
  │
  ▼ print_piglog_terms/1 (piglog2_printer)
     or load_generated_terms/3 (piglog2_loader)
     or write to file
```

## Section Structure

A section represents one conjunction element (goal) with its variable flow:

```prolog
section(
  Goals,           % list of goals (typically one)
  Inputs,          % variables this section consumes (already bound)
  Outputs,         % variables this section produces (first bound here)
  meta(Index, CutBoundary)  % position and cut flag
)
```

## Independence Checking

Two sections I and J are **independent** (can run concurrently) if:
1. Neither directly nor transitively depends on the other (via variable flow)
2. No cut boundary exists between them
3. Both are thread-safe (per safety classification)
4. Both individually exceed the cost threshold

### Transitive Dependency

`section_trans_dep_(Sections, DepIdx, BaseIdx, Visited)` checks:
- Direct: outputs of BaseIdx overlap with inputs of DepIdx
- Transitive: ∃ Mid such that Mid's outputs overlap DepIdx's inputs AND Mid transitively depends on BaseIdx

## Clique Detection

Sections are grouped for `concurrent/3` using clique detection:
1. Build independent pairs (I-J where I and J are independent)
2. Form connected components (union-find)
3. Prune each component to a clique (all pairs must be in the independent-pairs set)
4. Filter clique to only include sections exceeding cost threshold

## Generated Code Structure

For a clause with independent sections [I, J, K] and sequential continuation [L, M]:

```prolog
head(Args) :-
    concurrent(3, [goal_i(Vars), goal_j(Vars), goal_k(Vars)], []),
    goal_l(Vars),
    goal_m(Vars).
```

The `concurrent/3` call from `library(thread)` runs all goals simultaneously.
Variable bindings made within concurrent goals are visible to the caller because
SWI-Prolog's `concurrent/3` runs goals in separate threads but shares the Prolog
heap — unbound variables in the calling environment are updated.

## Thread Safety Classification

`piglog2_safety.pl` maintains three knowledge bases:

1. **Known thread-safe built-ins**: arithmetic, pure unification, type tests, list ops, etc.
2. **Known thread-unsafe built-ins**: assert/retract, I/O side effects, global state
3. **Known effectful predicates**: format, write, nl, etc.

User-declared safety (via `:- piglog_thread_safe(pred/arity)`) overrides static classification.

A section is safe for concurrency if ALL its goals are thread-safe.

## Cost Estimation

`estimate_goal_cost/3` uses the following priority order:
1. User declaration: `:- piglog_cost(pred/arity, Ms)` or `:- piglog_long(pred/arity)`
2. Measured time: from calibration runs or `piglog_calibrate/0`
3. Static estimate: from `builtin_cost_class/2` and `cost_class_ms/2`

The default cost for an unknown predicate with no declarations is 1.0 ms.
The default concurrency threshold is 5.0 ms.
The default concurrency overhead is 1.0 ms.

Conversion is applied when: `max(section_costs) > threshold` AND at least 2 sections
exceed the threshold individually.
