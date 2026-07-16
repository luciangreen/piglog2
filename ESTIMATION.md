# Piglog 2: Cost Estimation

## Overview

Piglog 2 estimates the runtime cost of each clause section to decide whether
making it concurrent is worthwhile. Cost estimation happens **at conversion time**
— no profiling is done at runtime.

---

## Cost Sources (Priority Order)

### 1. User-Declared Cost

```prolog
:- piglog_cost(my_pred/2, 50.0).  % 50 milliseconds
```

This is the highest-priority source. If a user has declared a specific cost,
it is always used.

### 2. User Long Declaration

```prolog
:- piglog_long(my_pred/2).
```

Marks the predicate as "expensive". The converter uses a configurable long-cost
value (default: 100.0 ms).

### 3. Measured Cost

If `piglog_calibrate/0` has been run and has measured the predicate's execution
time, that measured time is stored and used.

### 4. Static Estimate

Built-in predicates are assigned to cost classes:

| Class | Approx. Cost | Examples |
|-------|-------------|---------|
| `tiny` | 0.001 ms | `true/0`, `fail/0` |
| `micro` | 0.01 ms | `var/1`, `atom/1`, `=/2`, `is/2` |
| `small` | 0.1 ms | `length/2`, `append/3`, `member/2` |
| `medium` | 1.0 ms | `sort/2`, `msort/2`, `number_codes/2` |
| `large` | 10.0 ms | `read_term/3`, `assert/1`, `format/2` |
| `unknown` | 1.0 ms | anything not classified |

---

## Thresholds

### Concurrency Threshold

The minimum cost for a section to be considered for concurrent execution.
Default: **5.0 ms**

Configure: `piglog_set_config(cost_threshold, 10.0).`

A section must exceed this threshold **individually** to be included in a
concurrent group. Cheap sections remain sequential even if they happen to be
independent of expensive ones.

### Saving Threshold

The conversion is applied only if the estimated saving exceeds a minimum:

```
estimated_saving = sum(section_costs) - (max(section_costs) + overhead)
```

If `estimated_saving` is negative (overhead exceeds saving), the conversion is
skipped.

---

## Calibration

Run `piglog_calibrate/0` to measure the actual concurrency overhead on your
system:

```prolog
?- piglog_calibrate.
Piglog 2: calibrating concurrency overhead...
  thread creation overhead: 0.42 ms (averaged over 100 runs)
  concurrent/3 overhead: 0.38 ms (averaged over 100 runs)
Piglog 2: calibration complete. Using overhead: 0.42 ms.
```

After calibration, the measured overhead is stored and used automatically.
Reset with `piglog_reset_config(overhead)`.

---

## Example

For the clause:

```prolog
report(S, R) :-
    analyse_words(S, W),    % declared: piglog_long → 100.0 ms
    analyse_numbers(S, N),  % declared: piglog_long → 100.0 ms
    combine(W, N, R).       % static estimate: small → 0.1 ms
```

- `analyse_words`: 100.0 ms > threshold (5.0 ms) → candidate
- `analyse_numbers`: 100.0 ms > threshold → candidate
- `combine`: 0.1 ms < threshold → stays sequential
- Estimated sequential: 200.1 ms
- Estimated concurrent: 100.0 ms + 1.0 ms (overhead) = 101.0 ms
- Estimated saving: 99.1 ms → worthwhile → **converted**
