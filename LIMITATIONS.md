# Piglog 2: Limitations

## What Piglog 2 Does Not Do

### No Runtime Heuristics

Piglog 2 makes all concurrency decisions **at conversion time**. The generated code
does not check at runtime whether concurrency is worthwhile. If sections were converted
to `concurrent/3`, they always run concurrently when the generated code executes.

There is no runtime profitability check, no adaptive scheduler, and no fallback to
sequential execution based on measured runtime.

### No Semantic Equivalence Verification

Piglog 2 does not prove that the concurrent version is semantically equivalent to
the sequential original. It relies on:
- User declarations of thread-safety and determinism
- Static classification of built-in predicates
- Analysis of variable flow to detect dependencies

If user declarations are wrong (e.g., marking a non-deterministic predicate as
deterministic), the generated code may produce incorrect results.

### No Mode Analysis

Piglog 2 does not perform mode analysis. It cannot statically determine whether a
head variable is bound (input) or unbound (output) when a clause is called. Variables
listed in the clause head are treated as "available" (input) to all sections.

**Implication**: Two sections that both produce the same output variable — e.g.,
both calling `foo(_, X)` where X is an unbound head variable — may be incorrectly
classified as independent. Such clauses should be marked with `:- piglog_thread_unsafe`
declarations or avoided in concurrent contexts.

### No Occurs Check

Variable analysis uses Prolog's standard unification (without occurs check). This is
consistent with SWI-Prolog's default behaviour.

### Cut Boundaries

A cut (`!`) between sections prevents those sections from being grouped concurrently.
Sections before and after a cut are treated as separate sequential regions. Cuts WITHIN
a section's goals are preserved but prevent other sections from being paired with that section.

### No Cross-Clause Parallelism

Piglog 2 analyses and transforms one clause at a time. It does not combine work from
multiple clauses of the same predicate, and it does not analyse call graphs across
predicate boundaries to find larger parallelism opportunities.

### SWI-Prolog Only

The generated code uses `concurrent/3` from SWI-Prolog's `library(thread)`. It is
not portable to other Prolog implementations without modification.

### No Goal Reordering

Piglog 2 does not reorder goals within a clause to create more parallelism opportunities.
Goals are transformed in-place: the sequential structure of non-independent sections
is preserved exactly as written.

### Threshold May Reject Valid Opportunities

The cost threshold (default: 5.0 ms) prevents very fast predicates from being made
concurrent even if they are independent. This is intentional — the concurrency overhead
would exceed the savings. Threshold can be adjusted via `piglog_set_config(cost_threshold, Ms)`.

### No Parallel Aggregation

The transformation does not automatically handle accumulators or aggregation patterns
(e.g., `foldl`, `aggregate_all`). These require specialised concurrent reduction patterns
that Piglog 2 does not generate.

## Known Issues

1. **Head variable ambiguity**: A variable appearing in the head may be classified as
   "input" even when it's an unbound output parameter. This can allow incorrect concurrent
   grouping in edge cases.

2. **Anonymous variable handling**: Anonymous variables (`_`) in different sections are
   distinct and never shared — this is correct behaviour.

3. **Meta-predicates**: Calls like `maplist/2,3`, `foldl/4,5`, `aggregate/3` are recognised
   as candidates for `concurrent_maplist` but require explicit `piglog_long` declarations on
   the called predicate to trigger the transformation.

4. **Module-qualified calls**: `Module:Goal` is treated as a single opaque goal for safety
   classification purposes. If the qualified call is thread-safe, mark the specific `Module:Pred/Arity`.
