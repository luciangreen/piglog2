%% piglog2_estimator.pl
%% Runtime estimation for Piglog 2.
%%
%% Estimation order:
%%   1. User cost declaration  (:- piglog_cost(Name/Arity, milliseconds(N)))
%%   2. User long declaration  (:- piglog_long(Name/Arity))  → large static value
%%   3. Measured benchmark     (safe measured execution)
%%   4. Static estimate        (based on clause structure)
%%
%% All estimation is performed at conversion time.
%% The generated program contains no cost-estimation code.

:- module(piglog2_estimator, [
    estimate_goal_cost/3,
    estimate_section_cost/3,
    estimate_group_saving/4,
    threshold_exceeded/2,
    saving_worthwhile/2,
    measure_goal/3,
    static_estimate/3,
    piglog2_calibration/2,
    store_calibration/2,
    get_concurrency_overhead/1
]).

:- use_module(piglog2_config).
:- use_module(piglog2_safety).

%% ─── Measurement cache (dynamic) ─────────────────────────────────────────────

:- dynamic piglog2_cached_measurement/4.
% piglog2_cached_measurement(Indicator, InputShape, RuntimeMs, Timestamp)

%% ─── Calibration data (dynamic) ──────────────────────────────────────────────

:- dynamic piglog2_calibration/2.
% piglog2_calibration(Key, ValueMs)

store_calibration(Key, Ms) :-
    retractall(piglog2_calibration(Key, _)),
    assertz(piglog2_calibration(Key, Ms)).

get_concurrency_overhead(OverheadMs) :-
    (piglog2_calibration(thread_overhead, Ms) ->
        OverheadMs = Ms
    ;
        piglog2_config(concurrency_overhead_ms, OverheadMs)
    ).

%% ─── Main estimation entry points ────────────────────────────────────────────

%% estimate_goal_cost(+Goal, +Options, -CostMs)
%% Estimate the cost (in milliseconds) of executing Goal.
%%
%% When Options contains timing_module(Mod), benchmarking calls Mod:Goal so
%% that predicates pre-loaded for auto-timing are exercised directly.

estimate_goal_cost(Goal, Options, CostMs) :-
    callable(Goal),
    functor(Goal, Name, Arity),
    Indicator = Name/Arity,
    (user_declared_cost(Indicator, CostMs) ->
        true
    ;
        user_declared_long(Indicator) ->
        CostMs = 100.0
    ;
        option_estimate_method(Options, measured),
        goal_is_safe_to_benchmark(Goal) ->
        benchmark_goal(Goal, Options, CostMs)
    ;
        static_estimate(Goal, Options, CostMs)
    ).

%% benchmark_goal(+Goal, +Options, -CostMs)
%% Run Goal for timing, optionally in the pre-loaded timing module.
%% Falls back to static_estimate if benchmarking fails.

benchmark_goal(Goal, Options, CostMs) :-
    (option_timing_module(Options, TempModule), TempModule \= none ->
        BenchGoal = TempModule:Goal
    ;
        BenchGoal = Goal
    ),
    (measure_goal_safe(BenchGoal, Options, Measured) ->
        CostMs = Measured
    ;
        static_estimate(Goal, Options, CostMs)
    ).

%% option_timing_module(+Options, -Module)
%% Extract the timing_module from Options, or 'none' if not present.

option_timing_module(Options, Module) :-
    (member(timing_module(Module), Options) ->
        true
    ;
        Module = none
    ).

%% estimate_section_cost(+Section, +Options, -CostMs)

estimate_section_cost(section(Goals, _, _, _), Options, CostMs) :-
    maplist(estimate_goal_cost_opt(Options), Goals, Costs),
    sumlist(Costs, CostMs).

estimate_goal_cost_opt(Options, Goal, Cost) :-
    estimate_goal_cost(Goal, Options, Cost).

%% estimate_group_saving(+Cost1, +Cost2, +Options, -SavingMs)
%%
%% For two independent sections with costs T1 and T2:
%%   sequential = T1 + T2
%%   concurrent = max(T1, T2) + overhead
%%   saving     = sequential - concurrent

estimate_group_saving(T1, T2, _Options, Saving) :-
    get_concurrency_overhead(Overhead),
    Sequential is T1 + T2,
    Concurrent is max(T1, T2) + Overhead,
    Saving is Sequential - Concurrent.

%% threshold_exceeded(+CostMs, +Options)
%% True if CostMs exceeds the minimum concurrent time threshold.

threshold_exceeded(CostMs, Options) :-
    option_min_concurrent_time(Options, MinMs),
    CostMs >= MinMs.

%% saving_worthwhile(+SavingMs, +Options)
%% True if the saving exceeds the minimum expected saving.

saving_worthwhile(SavingMs, Options) :-
    option_min_expected_saving(Options, MinSaving),
    SavingMs >= MinSaving.

%% ─── User declarations ────────────────────────────────────────────────────────

user_declared_cost(Indicator, CostMs) :-
    piglog_user_cost(Indicator, milliseconds(CostMs)),
    !.
user_declared_cost(Indicator, CostMs) :-
    piglog_user_cost(Indicator, CostMs),
    number(CostMs).

user_declared_long(Indicator) :-
    piglog_user_long(Indicator).

%% ─── Benchmark safety ────────────────────────────────────────────────────────

goal_is_safe_to_benchmark(Goal) :-
    \+ goal_has_side_effect(Goal),
    \+ goal_introduces_io(Goal),
    \+ goal_is_recursive_unknown(Goal).

goal_introduces_io(Goal) :-
    goal_has_side_effect(Goal).

goal_is_recursive_unknown(_) :- fail.  % conservative; extend as needed

%% ─── Measured benchmarking ────────────────────────────────────────────────────

%% measure_goal(+Goal, +Repetitions, -MedianMs)
%% Time a goal over Repetitions runs; return median time in milliseconds.

measure_goal(Goal, Repetitions, MedianMs) :-
    numlist(1, Repetitions, _),
    findall(T, (
        between(1, Repetitions, _),
        statistics(walltime, [Start|_]),
        (call(Goal) -> true ; true),
        statistics(walltime, [End|_]),
        T is End - Start
    ), Times),
    msort(Times, Sorted),
    length(Sorted, Len),
    Mid is Len // 2,
    nth0(Mid, Sorted, MedianMs).

%% measure_goal_safe(+Goal, +Options, -MedianMs)

measure_goal_safe(Goal, Options, MedianMs) :-
    option_benchmark_repetitions(Options, Reps),
    (catch(
        measure_goal(Goal, Reps, MedianMs),
        _Error,
        fail
    ) -> true ; fail).

%% ─── Static estimation ───────────────────────────────────────────────────────

%% static_estimate(+Goal, +Options, -CostMs)
%%
%% Estimate based on:
%% - Known built-in categories
%% - Clause structure (number of body goals, recursion, list operations)

static_estimate(Goal, _Options, CostMs) :-
    callable(Goal),
    functor(Goal, Name, Arity),
    Indicator = Name/Arity,
    (builtin_cost_class(Indicator, Class) ->
        cost_class_ms(Class, CostMs)
    ;
        clause_body_cost(Name, Arity, CostMs)
    ).

builtin_cost_class(true/0,    trivial).
builtin_cost_class(fail/0,    trivial).
builtin_cost_class(false/0,   trivial).
builtin_cost_class(!/0,       trivial).
builtin_cost_class('='/2,       trivial).
builtin_cost_class('=='/2,      trivial).
builtin_cost_class('\\='/2,      trivial).
builtin_cost_class('\\=='/2,     trivial).
builtin_cost_class(is/2,      trivial).
builtin_cost_class('<'/2,       trivial).
builtin_cost_class('>'/2,       trivial).
builtin_cost_class('=<'/2,      trivial).
builtin_cost_class('>='/2,      trivial).
builtin_cost_class('=:='/2,     trivial).
builtin_cost_class('=\\='/2,     trivial).
builtin_cost_class(atom/1,    trivial).
builtin_cost_class(number/1,  trivial).
builtin_cost_class(var/1,     trivial).
builtin_cost_class(nonvar/1,  trivial).
builtin_cost_class(ground/1,  trivial).
builtin_cost_class(functor/3, trivial).
builtin_cost_class(arg/3,     trivial).
builtin_cost_class('=..'/2,     trivial).
builtin_cost_class(copy_term/2, trivial).
builtin_cost_class(length/2,  light).
builtin_cost_class(append/3,  light).
builtin_cost_class(nth0/3,    light).
builtin_cost_class(nth1/3,    light).
builtin_cost_class(last/2,    light).
builtin_cost_class(member/2,  light).
builtin_cost_class(memberchk/2, light).
builtin_cost_class(sort/2,    medium).
builtin_cost_class(msort/2,   medium).
builtin_cost_class(sort/4,    medium).
builtin_cost_class(maplist/2, medium).
builtin_cost_class(maplist/3, medium).
builtin_cost_class(maplist/4, medium).
builtin_cost_class(foldl/4,   medium).
builtin_cost_class(foldl/5,   medium).
builtin_cost_class(include/3, medium).
builtin_cost_class(exclude/3, medium).
builtin_cost_class(aggregate_all/3, medium).
builtin_cost_class(write/1,   io).
builtin_cost_class(writeln/1, io).
builtin_cost_class(format/1,  io).
builtin_cost_class(format/2,  io).
builtin_cost_class(read/1,    io).
builtin_cost_class(open/3,    io).
builtin_cost_class(close/1,   io).
builtin_cost_class(assert/1,  medium).
builtin_cost_class(assertz/1, medium).
builtin_cost_class(asserta/1, medium).
builtin_cost_class(retract/1, medium).

cost_class_ms(trivial, 0.001).
cost_class_ms(light,   0.1).
cost_class_ms(medium,  0.5).
cost_class_ms(io,      1.0).
cost_class_ms(unknown, 1.0).

%% clause_body_cost(+Name, +Arity, -CostMs)
%% Estimate user-defined predicate cost from its clauses.

clause_body_cost(Name, Arity, CostMs) :-
    functor(Head, Name, Arity),
    (clause(Head, Body) ->
        count_body_calls(Body, N),
        CostMs is N * 0.5
    ;
        CostMs = 1.0
    ).

count_body_calls((A, B), N) :-
    !,
    count_body_calls(A, NA),
    count_body_calls(B, NB),
    N is NA + NB.
count_body_calls(true, 0) :- !.
count_body_calls(_, 1).

%% ─── Option helpers ──────────────────────────────────────────────────────────

option_estimate_method(Options, Method) :-
    (member(estimate(Method), Options) -> true ;
     piglog2_config(estimation_method, Method)).

option_min_concurrent_time(Options, Ms) :-
    (member(minimum_concurrent_time(milliseconds(Ms)), Options) -> true ;
     member(minimum_concurrent_time(Ms), Options), number(Ms) -> true ;
     piglog2_config(minimum_concurrent_time, milliseconds(Ms)) -> true ;
     Ms = 10.0).

option_min_expected_saving(Options, Ms) :-
    (member(minimum_expected_saving(milliseconds(Ms)), Options) -> true ;
     member(minimum_expected_saving(Ms), Options), number(Ms) -> true ;
     piglog2_config(minimum_expected_saving, milliseconds(Ms)) -> true ;
     Ms = 2.0).

option_benchmark_repetitions(Options, Reps) :-
    (member(benchmark_repetitions(Reps), Options) -> true ;
     piglog2_config(benchmark_repetitions, Reps)).

option_max_threads(Options, N) :-
    (member(maximum_threads(N), Options) -> true ;
     piglog2_config(maximum_threads, N)).

sumlist([], 0).
sumlist([H|T], Sum) :-
    sumlist(T, Rest),
    Sum is H + Rest.
