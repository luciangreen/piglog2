# Piglog 2: Concurrency Transforms

This document shows how Piglog 2 transforms sequential Prolog code into
concurrent code using `concurrent/3` from SWI-Prolog's `library(thread)`.

---

## Basic: Two Independent Long Sections

### Input

```prolog
:- piglog_long(analyse_words/2).
:- piglog_thread_safe(analyse_words/2).
:- piglog_long(analyse_numbers/2).
:- piglog_thread_safe(analyse_numbers/2).

report(Source, Report) :-
    analyse_words(Source, Words),
    analyse_numbers(Source, Numbers),
    combine(Words, Numbers, Report).
```

### Output

```prolog
:- use_module(library(thread)).

report(Source, Report) :-
    concurrent(2, [analyse_words(Source, Words),
                   analyse_numbers(Source, Numbers)], []),
    combine(Words, Numbers, Report).
```

**Why**: `analyse_words` and `analyse_numbers` are declared long and thread-safe.
They only share `Source` (input, read-only) and produce separate variables
(`Words`, `Numbers`). They are independent. `combine/3` depends on both and
remains sequential after the concurrent block.

---

## Three Independent Sections

### Input

```prolog
:- piglog_long(build_index/0).
:- piglog_long(warm_cache/0).
:- piglog_long(load_tables/0).
:- piglog_thread_safe(build_index/0).
:- piglog_thread_safe(warm_cache/0).
:- piglog_thread_safe(load_tables/0).

initialise :-
    build_index,
    warm_cache,
    load_tables.
```

### Output

```prolog
initialise :-
    concurrent(3, [build_index, warm_cache, load_tables], []).
```

---

## Mixed: Only Long Sections Converted

### Input

```prolog
:- piglog_long(heavy_a/2).
:- piglog_long(heavy_b/2).
:- piglog_thread_safe(heavy_a/2).
:- piglog_thread_safe(heavy_b/2).

process(X, Result) :-
    validate(X),              % cheap, stays sequential
    heavy_a(X, A),
    heavy_b(X, B),
    R = A + B.                % cheap, stays sequential
```

### Output

```prolog
process(X, Result) :-
    validate(X),
    concurrent(2, [heavy_a(X, A), heavy_b(X, B)], []),
    R = A + B.
```

---

## Sequential Chain: Unchanged

### Input

```prolog
:- piglog_long(load/2).
:- piglog_long(transform/2).
:- piglog_long(save/2).
:- piglog_thread_safe(load/2).
:- piglog_thread_safe(transform/2).
:- piglog_thread_safe(save/2).

pipeline(Input, Output) :-
    load(Input, Data),
    transform(Data, Processed),
    save(Processed, Output).
```

### Output (unchanged)

```prolog
pipeline(Input, Output) :-
    load(Input, Data),
    transform(Data, Processed),
    save(Processed, Output).
```

**Why**: `transform/2` needs `Data` from `load/2`. `save/2` needs `Processed`
from `transform/2`. These are transitive dependencies — no two sections are
independent.

---

## Cut Boundary: Preserved

### Input

```prolog
:- piglog_long(expensive_a/1).
:- piglog_long(expensive_b/1).
:- piglog_thread_safe(expensive_a/1).
:- piglog_thread_safe(expensive_b/1).

guarded(X) :-
    expensive_a(X),
    !,
    expensive_b(X).
```

### Output (unchanged)

```prolog
guarded(X) :-
    expensive_a(X),
    !,
    expensive_b(X).
```

**Why**: A cut between `expensive_a` and `expensive_b` prevents them from being
grouped — the cut marks a control-flow boundary that cannot be crossed.

---

## How Variable Sharing Works with concurrent/3

SWI-Prolog's `concurrent/3` runs goals in separate threads but shares the Prolog
heap with the calling thread. This means:

```prolog
concurrent(2, [foo(X), bar(Y)], [])
```

After this call, `X` and `Y` are bound in the calling thread's environment. This
is why Piglog 2 can use `concurrent/3` without message-passing — output variables
are simply unified in-place by the worker threads.

**Requirement**: The concurrent goals must not share OUTPUT variables with each
other (two goals both trying to bind the same unbound variable would conflict).
They CAN share read-only INPUT variables.
