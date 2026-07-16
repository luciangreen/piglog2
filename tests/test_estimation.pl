%% test_estimation.pl
%% Runtime estimation tests for Piglog 2.

:- use_module(library(plunit)).
:- use_module('../piglog2_estimator').
:- use_module('../piglog2_safety').
:- use_module('../piglog2_config').

:- begin_tests(estimation).

%% ─── Static estimates ────────────────────────────────────────────────────────

test(trivial_is_cheap) :-
    static_estimate((_ is 1+2), [], Cost),
    Cost < 0.01.

test(sort_medium_cost) :-
    static_estimate(sort([a,b], _), [], Cost),
    Cost >= 0.1.

test(unknown_predicate_has_cost) :-
    static_estimate(unknown_pred(_, _), [], Cost),
    Cost >= 0.0.

%% ─── User declarations ───────────────────────────────────────────────────────

test(declared_cost_used) :-
    declare_cost(expensive_pred/2, milliseconds(50.0)),
    estimate_goal_cost(expensive_pred(_, _), [], Cost),
    Cost =:= 50.0.

test(declared_long_gives_high_cost) :-
    declare_long(very_slow/1),
    estimate_goal_cost(very_slow(_), [], Cost),
    Cost >= 50.0.

%% ─── Threshold ───────────────────────────────────────────────────────────────

test(exceeds_threshold) :-
    threshold_exceeded(15.0, []).  % default threshold is 10ms

test(does_not_exceed_threshold) :-
    \+ threshold_exceeded(5.0, []).

test(custom_threshold) :-
    threshold_exceeded(5.0, [minimum_concurrent_time(milliseconds(2))]).

test(saving_worthwhile) :-
    saving_worthwhile(5.0, []).  % default min saving is 2ms

test(saving_not_worthwhile) :-
    \+ saving_worthwhile(1.0, []).

%% ─── Group saving calculation ────────────────────────────────────────────────

test(two_equal_sections_saving) :-
    estimate_group_saving(20.0, 20.0, [], Saving),
    Saving > 0.  % concurrent should be faster

test(very_short_sections_no_saving) :-
    estimate_group_saving(0.001, 0.001, [], Saving),
    Saving < 0.  % overhead exceeds savings

%% ─── Calibration ─────────────────────────────────────────────────────────────

test(calibration_stores_value) :-
    store_calibration(test_key, 3.14),
    piglog2_calibration(test_key, Val),
    Val =:= 3.14.

test(overhead_uses_calibration) :-
    store_calibration(thread_overhead, 2.5),
    get_concurrency_overhead(OH),
    OH =:= 2.5.

:- end_tests(estimation).
