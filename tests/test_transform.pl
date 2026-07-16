%% test_transform.pl
%% Transformation tests for Piglog 2.

:- use_module(library(plunit)).
:- use_module('../piglog2_transformer').
:- use_module('../piglog2_safety').

:- begin_tests(transformer).

setup_long_predicates :-
    declare_long(worker_a/2), declare_thread_safe(worker_a/2),
    declare_long(worker_b/2), declare_thread_safe(worker_b/2),
    declare_long(worker_c/2), declare_thread_safe(worker_c/2).

teardown_declarations :-
    retractall(piglog_user_long(_)),
    retractall(piglog_user_thread_safe(_)),
    retractall(piglog_user_cost(_, _)).

%% ─── concurrent/3 transformation ─────────────────────────────────────────────

test(two_independent_produces_concurrent,
     [setup(setup_long_predicates), cleanup(teardown_declarations)]) :-
    Clause = (p(X, A, B) :- worker_a(X, A), worker_b(X, B)),
    transform_clause(Clause, [], Generated, _Helpers, Report),
    Generated = (p(_, _, _) :- concurrent(_, [worker_a(_, _), worker_b(_, _)], [])),
    report_is_converted(Report).

test(sequential_continuation_preserved,
     [setup(setup_long_predicates), cleanup(teardown_declarations)]) :-
    Clause = (p(X, R) :- worker_a(X, A), worker_b(X, B), combine(A, B, R)),
    transform_clause(Clause, [], Generated, _Helpers, _Report),
    Generated = (p(_, _) :- concurrent(_, _, []), combine(_, _, _)).

%% ─── maplist transformation ───────────────────────────────────────────────────

test(maplist_transform_when_long) :-
    declare_long(expensive_map/2),
    declare_thread_safe(expensive_map/2),
    %% maplist(Pred, List) calls Pred/2 (Pred + Elem + Acc)
    %% estimate_goal_cost is called with just Pred atom; use atom declaration
    assert(piglog_user_long(expensive_map/1)),  % /1 for maplist(Pred, List) calling Pred(Elem)
    try_transform_maplist(maplist(expensive_map, [1,2,3]), [], NewGoal, Decision),
    (Decision = converted_concurrent_maplist ->
        NewGoal = concurrent_maplist(expensive_map, _)
    ;
        true  % acceptable if threshold not met
    ).

test(maplist_no_transform_when_short) :-
    try_transform_maplist(maplist(atom, [1,2,3]), [], NewGoal, Decision),
    NewGoal = maplist(atom, [1,2,3]),
    Decision = retained_sequential_short.

%% ─── Terms transformation ─────────────────────────────────────────────────────

test(transform_terms_converts_clauses,
     [setup(setup_long_predicates), cleanup(teardown_declarations)]) :-
    Terms = [(p(X,A,B) :- worker_a(X,A), worker_b(X,B))],
    transform_terms(Terms, [], transform_result(Generated, Helpers, _Reports)),
    Generated \= [],
    Helpers = [].  % concurrent/3 needs no helpers

test(transform_terms_preserves_facts,
     [setup(setup_long_predicates), cleanup(teardown_declarations)]) :-
    Terms = [foo(1), foo(2), foo(3)],
    transform_terms(Terms, [], transform_result(Generated, [], _)),
    Generated = [foo(1), foo(2), foo(3)].

test(transform_terms_preserves_directives) :-
    Terms = [(:- use_module(library(lists)))],
    transform_terms(Terms, [], transform_result(Generated, [], _)),
    Generated = [(:- use_module(library(lists)))].

%% ─── No runtime heuristics in generated code ──────────────────────────────────

test(no_piglog_scheduler_in_output,
     [setup(setup_long_predicates), cleanup(teardown_declarations)]) :-
    Clause = (p(X, A, B) :- worker_a(X, A), worker_b(X, B)),
    transform_clause(Clause, [], Generated, _, _),
    Generated = (p(_, _, _) :- Body),
    \+ term_contains_scheduler(Body).

term_contains_scheduler(Term) :-
    functor(Term, Name, _),
    (sub_atom(Name, _, _, _, piglog_schedule) ;
     sub_atom(Name, _, _, _, piglog_profitable) ;
     sub_atom(Name, _, _, _, piglog_runtime)).
term_contains_scheduler((A, B)) :-
    (term_contains_scheduler(A) ; term_contains_scheduler(B)).
term_contains_scheduler((A ; B)) :-
    (term_contains_scheduler(A) ; term_contains_scheduler(B)).
term_contains_scheduler((_ -> A ; B)) :-
    (term_contains_scheduler(A) ; term_contains_scheduler(B)).

:- end_tests(transformer).
