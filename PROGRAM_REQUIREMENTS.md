# Piglog 2: Program Requirements

This document records the original requirements that drove the implementation
of Piglog 2. It corresponds to the `pr1.txt` requirements file.

---

## Overview

Piglog 2 is a SWI-Prolog source-to-source converter that:

1. **Analyses** ordinary Prolog code
2. **Estimates** runtime costs at conversion time
3. **Inserts** direct SWI-Prolog concurrency constructs (`concurrent/3`,
   `concurrent_maplist/2,3`) into sufficiently expensive independent sections

The generated code contains **no runtime scheduler** and **no heuristics**.
All concurrency decisions are made once, during conversion.

---

## Core Requirements

### R1: Source Reading

- Accept source from: files, inline term lists, loaded modules, specific predicates
- Preserve all terms (facts, rules, directives) through the pipeline

### R2: Clause Analysis

- Flatten conjunction bodies into a list of sections (goals)
- For each section, determine:
  - Input variables (already bound before this section runs)
  - Output variables (first bound by this section)
  - Whether the section contains a cut boundary
- Use variable identity (not unification) for all variable comparisons

### R3: Independence Analysis

- Two sections are independent if:
  - No direct data dependency (outputs of one are not inputs of the other)
  - No transitive data dependency (through intermediate sections)
  - No cut boundary between them
- Independence checking uses transitive closure over the dependency graph

### R4: Thread Safety Classification

- Maintain databases of known thread-safe and thread-unsafe predicates
- Support user declarations: `piglog_thread_safe/1`, `piglog_thread_unsafe/1`
- A section is safe for concurrency only if ALL its goals are thread-safe
- User declarations take priority over static classification

### R5: Cost Estimation

- Priority: user declared cost > user long declaration > measured > static
- Static cost classes: tiny, micro, small, medium, large, unknown
- Threshold: sections below the cost threshold are never made concurrent
- Saving check: conversion only applied if estimated saving > 0

### R6: Transformation

- Find maximal CLIQUES of pairwise-independent sections (not just connected components)
- Filter cliques to include only sections exceeding the cost threshold
- Replace qualifying cliques with `concurrent(N, Goals, [])` calls
- Preserve sequential sections (before and after the concurrent block) in-place
- The transformer must preserve variable identity (no findall on terms with variables)

### R7: No Runtime Scheduler

- Generated code MUST NOT contain any runtime profitability checks
- Generated code MUST NOT contain any adaptive scheduler predicates
- Generated code MUST NOT fall back to sequential execution at runtime
- All decisions are final at conversion time

### R8: maplist Transformation

- `maplist(Pred, List)` and `maplist(Pred, List, Outputs)` can be transformed
  to `concurrent_maplist(Pred, List)` and `concurrent_maplist(Pred, List, Outputs)`
  if `Pred` is declared long and thread-safe

### R9: Output Formats

- Print converted terms to stdout
- Write converted terms to a file
- Return converted terms as a Prolog list
- Load converted terms into a fresh SWI-Prolog module

### R10: Reports

- Generate per-predicate conversion reports showing:
  - Predicate indicator
  - Decision (converted / retained sequential)
  - Group indices and estimated costs
  - Concurrency construct used

### R11: Configuration

- Configurable: cost threshold, max threads, concurrency overhead, long cost
- User can set, get, and reset individual config keys
- Defaults are sensible for most workloads

### R12: Calibration

- `piglog_calibrate/0` measures actual thread-creation and `concurrent/3` overhead
- Measured overhead is stored and used in future cost calculations
- Calibration summary can be printed

### R13: User API

- `piglog_output/1,2` — print converted code
- `piglog_output_file/1,2` — convert files
- `piglog_run/2,3` — convert and run
- `piglog_output_run/2,3` — print then run
- `piglog_convert/3` — convert and return terms
- `piglog_write/2,3` — write to file
- `piglog_report/1,2` — print report
- `piglog_calibrate/0,1` — calibrate overhead
- `piglog_begin/0` — interactive term capture
- `piglog/2,3` — unified interface

### R14: Documentation

- README with quick start, installation, usage examples
- ARCHITECTURE.md describing module structure and pipeline
- CONCURRENCY_TRANSFORMS.md with before/after examples
- ESTIMATION.md describing cost estimation and thresholds
- LIMITATIONS.md listing what Piglog 2 does not do
- REPL.md with complete REPL command reference
- TESTING.md with instructions for running the test suite
- PROGRAM_REQUIREMENTS.md (this file)

### R15: Tests

- Test suite using SWI-Prolog `plunit` framework
- Tests for: basic conversion, variable analysis, safety, estimation,
  transformation, REPL commands, generated code correctness

---

## Design Constraints

- **SWI-Prolog 8.0+** required (threaded build, `library(thread)`)
- **No runtime overhead** in generated code beyond the `concurrent/3` call itself
- **Variable identity** preserved throughout the transformation pipeline
- **Cuts respected** as section boundaries
- **Operator quoting** required for predicate indicators involving operators (e.g., `'='/2`)
