# Piglog 2: REPL Usage

## Loading

```prolog
?- use_module(piglog2).
Piglog 2 loaded. Type '?- piglog_output(file(Path)).' to convert a file.
```

---

## piglog_output/1,2

Convert and print generated code to stdout.

```prolog
% From a file
?- piglog_output(file('my_program.pl')).

% From inline terms
?- piglog_output(terms([(p(X, A, B) :- expensive_a(X, A), expensive_b(X, B))]), []).

% From a loaded module
?- piglog_output(module(my_module)).

% With report
?- piglog_output(file('prog.pl'), [report(true)]).
```

---

## piglog_output_file/1,2

```prolog
% Print to stdout
?- piglog_output_file('my_program.pl').

% Write to new file
?- piglog_output_file('input.pl', 'output_concurrent.pl').
```

---

## piglog_run/2,3

Convert and immediately run the generated code.

```prolog
?- piglog_run(file('my_program.pl'), top_level_goal).

% With a specific module name
?- piglog_run(file('my_program.pl'), my_goal(X), [module_name(my_gen)]).

% Print output and run
?- piglog_output_run(file('my_program.pl'), top_level_goal).
```

---

## piglog_convert/3

Convert and return terms + report (without printing).

```prolog
?- piglog_convert(file('prog.pl'), Terms, Report),
   length(Terms, N),
   format("~w terms generated~n", [N]).
```

---

## piglog_write/2,3

Convert and write to a file.

```prolog
?- piglog_write(file('input.pl'), 'output.pl').

?- piglog_write(file('input.pl'), 'output.pl', [cost_threshold(10.0)]).
```

---

## piglog_report/1,2

Print a conversion report without writing output.

```prolog
?- piglog_report(file('my_program.pl')).

=== Piglog 2 Conversion Report ===

PIGLOG2 INFO:
  predicate: report/2
  action: converted
  group sections: [0,1]
  estimated sequential: 200.00 ms
  estimated concurrent: 101.00 ms
  estimated saving: 99.00 ms
  construct: concurrent3
  decision: converted_concurrent
...
```

---

## User Declarations (in source files)

```prolog
:- piglog_long(my_pred/2).              % declare as expensive
:- piglog_thread_safe(my_pred/2).       % declare as thread-safe
:- piglog_thread_unsafe(my_pred/2).     % prevent concurrent use
:- piglog_deterministic(my_pred/2).     % declare as deterministic
:- piglog_cost(my_pred/2, 50.0).        % explicit cost (ms)
```

---

## Configuration

```prolog
% Set a config option
?- piglog_set_config(cost_threshold, 10.0).  % require 10ms to convert
?- piglog_set_config(max_threads, 8).         % allow up to 8 threads
?- piglog_set_config(overhead, 0.5).          % concurrency overhead

% Query current config
?- piglog2_config(cost_threshold, V).
V = 5.0.

% Reset to default
?- piglog_reset_config(cost_threshold).
```

Available config keys:

| Key | Default | Description |
|-----|---------|-------------|
| `cost_threshold` | 5.0 | Minimum ms for concurrency candidate |
| `maximum_threads` | 4 | Max threads in concurrent/3 |
| `overhead` | 1.0 | Estimated concurrency overhead (ms) |
| `long_cost` | 100.0 | Cost assigned to `piglog_long` predicates |
| `short_cost` | 0.01 | Cost assigned to known-cheap predicates |

---

## Interactive Mode (piglog_begin)

Capture terms interactively:

```prolog
?- piglog_begin.
Piglog 2: enter clauses, end with 'end_of_file.'
|: :- piglog_long(work/2).
|: process(X, A, B) :- work(X, A), work(X, B).
|: end_of_file.
Piglog 2: 2 term(s) captured.
```

Then convert the captured terms:

```prolog
?- piglog_output(captured).
```

---

## Alternative Interface

```prolog
?- piglog(Source, output).
?- piglog(Source, convert(Terms)).
?- piglog(Source, convert(Terms, Report)).
?- piglog(Source, write(OutputFile)).
?- piglog(Source, run(Goal)).
```
