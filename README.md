# Piglog 2

Piglog 2 is a SWI-Prolog source-to-source converter that analyses ordinary Prolog code, estimates runtime costs at conversion time, and inserts direct SWI-Prolog concurrency constructs (`concurrent/3`, `concurrent_maplist/2,3`) into sufficiently expensive independent clause sections.

The generated code contains **no runtime scheduler and no heuristics** — concurrency decisions are made once, at conversion time, based on static analysis and user-supplied cost declarations.

---

## Quick Start

```prolog
?- use_module(piglog2).

% Print converted code for a file
?- piglog_output(file('my_program.pl')).

% Write converted code to a new file
?- piglog_write(file('my_program.pl'), 'my_program_concurrent.pl').

% Convert and immediately run
?- piglog_run(file('my_program.pl'), top_level_goal).
```

---

## Installation

Requires SWI-Prolog 8.0 or later (threaded build).

```bash
git clone https://github.com/luciangreen/piglog2.git
cd piglog2
swipl -g "use_module(piglog2), halt"   # verify it loads
```

---

## Usage

### REPL Commands

| Predicate | Description |
|-----------|-------------|
| `piglog_output(+Source)` | Print converted code to stdout |
| `piglog_output(+Source, +Options)` | As above with options |
| `piglog_output_file(+InputFile)` | Convert a `.pl` file and print |
| `piglog_output_file(+InputFile, +OutputFile)` | Convert to a new file |
| `piglog_run(+Source, +Goal)` | Convert and run Goal in generated module |
| `piglog_output_run(+Source, +Goal)` | Print output then run |
| `piglog_convert(+Source, -Terms, -Report)` | Convert and return terms/report |
| `piglog_write(+Source, +OutputFile)` | Write converted terms to file |
| `piglog_report(+Source)` | Print conversion report |
| `piglog_calibrate` | Calibrate concurrency overhead threshold |

### Source Types

```prolog
file('path/to/file.pl')      % Read from a file
terms([...])                  % Inline list of terms
module(my_module)             % All clauses from a loaded module
predicate(mod:pred/arity)     % A specific predicate
```

### User Declarations

Add these to your source file to guide the converter:

```prolog
:- piglog_long(my_pred/3).           % mark as expensive
:- piglog_thread_safe(my_pred/3).    % mark as thread-safe
:- piglog_thread_unsafe(my_pred/3).  % mark as thread-unsafe (prevents conversion)
:- piglog_deterministic(my_pred/3).  % mark as deterministic
:- piglog_cost(my_pred/3, 50.0).     % explicit cost in milliseconds
```

### Options

```prolog
[cost_threshold(Ms)]    % minimum cost to consider concurrency (default: 5.0 ms)
[max_threads(N)]        % maximum thread count (default: 4)
[overhead(Ms)]          % concurrency overhead estimate (default: 1.0 ms)
[report(true)]          % print conversion report
```

---

## How It Works

1. **Read** — load source terms from file, term list, module, or predicate
2. **Analyse** — flatten conjunction bodies, compute per-section variable flow (inputs/outputs), detect transitive dependencies and cut boundaries
3. **Estimate** — look up user cost declarations, measured times, or apply static heuristics per section
4. **Transform** — find maximal cliques of pairwise-independent sections whose cost exceeds the threshold; wrap them in `concurrent/3`
5. **Print/Load** — write generated terms or load them into a fresh module

The converter **never inserts runtime profitability checks**. If a section was converted at conversion time, it is always concurrent in the output.

### Example

Input:
```prolog
report(Source, Report) :-
    analyse_words(Source, Words),
    analyse_numbers(Source, Numbers),
    combine(Words, Numbers, Report).
```

Output (both `analyse_words` and `analyse_numbers` are independent):
```prolog
report(Source, Report) :-
    concurrent(2, [analyse_words(Source, Words),
                   analyse_numbers(Source, Numbers)], []),
    combine(Words, Numbers, Report).
```

---

## Caveats

* Insert statements like the following in algorithms to be converted, ensuring that the cost of predicates to make concurrent is > 10 ms and that the predicates are safe to make concurrent.

```
:- piglog_cost(word_score/2,milliseconds(40)).

:- piglog_cost(number_score/2,milliseconds(35)).

:- piglog_thread_safe(word_score/2).

:- piglog_thread_safe(number_score/2).
```

---

## Running Tests

```bash
cd piglog2
swipl -t halt -g "
  use_module(library(plunit)),
  use_module(piglog2),
  consult('tests/test_basic'),
  consult('tests/test_analysis'),
  consult('tests/test_safety'),
  consult('tests/test_estimation'),
  consult('tests/test_transform'),
  consult('tests/test_repl'),
  consult('tests/test_generated'),
  run_tests"
```

---

## Architecture

| Module | Responsibility |
|--------|---------------|
| `piglog2.pl` | Public API, conversion pipeline |
| `piglog2_reader.pl` | Source loading (file/terms/module/predicate) |
| `piglog2_analyser.pl` | Clause flattening, variable flow, independence |
| `piglog2_safety.pl` | Thread-safety/determinism classification, user declarations |
| `piglog2_estimator.pl` | Runtime cost estimation |
| `piglog2_transformer.pl` | Source-to-source transformation, `concurrent/3` insertion |
| `piglog2_printer.pl` | Pretty-printing generated terms |
| `piglog2_loader.pl` | Loading generated terms into a fresh module |
| `piglog2_report.pl` | Conversion reports |
| `piglog2_calibrate.pl` | Calibration of concurrency overhead |
| `piglog2_runtime.pl` | Helper predicates for generated code |
| `piglog2_config.pl` | Configuration management |

See [ARCHITECTURE.md](ARCHITECTURE.md) for details.

---

## Limitations

- No mode analysis: variables in clause heads may be misclassified as inputs even when unbound
- No semantic equivalence verification
- Cuts prevent concurrent grouping of surrounding sections
- Generated code requires SWI-Prolog (uses `concurrent/3` from `library(thread)`)
- `concurrent/3` goals must be truly independent (no shared unbound output variables)

See [LIMITATIONS.md](LIMITATIONS.md) for the complete list.

---

## License

See repository licence.
