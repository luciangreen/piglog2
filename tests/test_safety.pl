%% test_safety.pl
%% Safety classification tests for Piglog 2.

:- use_module(library(plunit)).
:- use_module('../piglog2_safety').

:- begin_tests(safety).

%% ─── Thread safety ───────────────────────────────────────────────────────────

test(arithmetic_thread_safe) :-
    goal_is_thread_safe(_ is 1+2).

test(atom_check_thread_safe) :-
    goal_is_thread_safe(atom(foo)).

test(write_not_thread_safe) :-
    \+ goal_is_thread_safe(writeln(hello)).

test(assert_not_thread_safe) :-
    \+ goal_is_thread_safe(assertz(foo)).

test(user_declared_thread_safe) :-
    declare_thread_safe(my_pred/2),
    goal_is_thread_safe(my_pred(_, _)).

test(user_declared_thread_unsafe) :-
    declare_thread_unsafe(unsafe_pred/1),
    \+ goal_is_thread_safe(unsafe_pred(_)).

%% ─── Side effects ────────────────────────────────────────────────────────────

test(writeln_has_side_effect) :-
    goal_has_side_effect(writeln(hello)).

test(arithmetic_no_side_effect) :-
    \+ goal_has_side_effect(_ is 1+2).

test(assert_has_side_effect) :-
    goal_has_side_effect(assertz(foo)).

test(retract_has_side_effect) :-
    goal_has_side_effect(retract(foo)).

%% ─── Determinism ─────────────────────────────────────────────────────────────

test(is_deterministic) :-
    goal_is_deterministic(_ is 1+2).

test(sort_deterministic) :-
    goal_is_deterministic(sort([3,1,2], _)).

test(user_pred_not_deterministic_by_default) :-
    \+ goal_is_deterministic(unknown_pred(_)).

test(user_declared_deterministic) :-
    declare_deterministic(my_det/1),
    goal_is_deterministic(my_det(_)).

%% ─── Section safety ──────────────────────────────────────────────────────────

test(pure_section_safe) :-
    Section = section([atom(X), number(Y)], [X,Y], [], meta(0, false)),
    section_safe_for_concurrency(Section).

test(section_with_write_unsafe) :-
    Section = section([writeln(hello), foo(_)], [], [], meta(0, false)),
    \+ section_safe_for_concurrency(Section).

test(cut_section_unsafe) :-
    Section = section([!], [], [], meta(0, true)),
    \+ section_safe_for_concurrency(Section).

:- end_tests(safety).
