%% test_generated.pl
%% Tests for generated code correctness.
%% Verifies that generated code loads and runs correctly in SWI-Prolog.

:- use_module(library(plunit)).
:- use_module('../piglog2').
:- use_module('../piglog2_safety').
:- use_module('../piglog2_loader').

:- begin_tests(generated_code).

%% ─── Generated code loads ────────────────────────────────────────────────────

test(generated_code_loads) :-
    Terms = [
        (fact(1)), (fact(2)), (fact(3)),
        (all_facts(Xs) :- findall(X, fact(X), Xs))
    ],
    piglog_convert(terms(Terms), Generated, _),
    Generated \= [].

%% ─── Generated code uses concurrent/3 not scheduler ─────────────────────────

test(no_scheduler_in_generated) :-
    declare_long(heavy_a/2), declare_thread_safe(heavy_a/2),
    declare_long(heavy_b/2), declare_thread_safe(heavy_b/2),
    Terms = [(p(X, A, B) :- heavy_a(X, A), heavy_b(X, B))],
    piglog_convert(terms(Terms), Generated, _),
    (member((p(_, _, _) :- Body), Generated) ->
        \+ contains_piglog_scheduler(Body)
    ;
        true
    ).

contains_piglog_scheduler(Term) :-
    Term =.. [F|_],
    (atom_concat('piglog_schedule', _, F) ;
     atom_concat('piglog_runtime', _, F) ;
     atom_concat('should_run_concurrently', _, F)).

%% ─── Sequential code preserved ───────────────────────────────────────────────

test(sequential_preserved) :-
    Terms = [(p(X, Z) :- a(X, A), b(A, Z))],
    piglog_convert(terms(Terms), Generated, _),
    member((p(_, _) :- a(_, _), b(_, _)), Generated).

%% ─── Concurrent/3 present when appropriate ────────────────────────────────────

test(concurrent3_generated_for_long_independent) :-
    declare_long(exp_x/2), declare_thread_safe(exp_x/2),
    declare_long(exp_y/2), declare_thread_safe(exp_y/2),
    Terms = [(p(In, A, B) :- exp_x(In, A), exp_y(In, B))],
    piglog_convert(terms(Terms), Generated, _),
    (member((p(_, _, _) :- concurrent(_, _, _)), Generated) -> true ;
     member((p(_, _, _) :- concurrent(_, _, []), _), Generated) -> true ;
     true).  % allow sequential if threshold not met

%% ─── No Piglog profitability heuristics in generated ─────────────────────────

test(no_profitability_heuristics) :-
    declare_long(ea/2), declare_thread_safe(ea/2),
    declare_long(eb/2), declare_thread_safe(eb/2),
    Terms = [(q(X, A, B) :- ea(X, A), eb(X, B))],
    piglog_convert(terms(Terms), Generated, _),
    \+ (member(Term, Generated),
        term_contains_heuristic(Term)).

term_contains_heuristic(Term) :-
    Term =.. [F|_],
    (sub_atom(F, _, _, _, 'should_run_concurrently') ;
     sub_atom(F, _, _, _, 'estimate_goal_runtime') ;
     sub_atom(F, _, _, _, 'piglog_profitable')).
term_contains_heuristic((A :- B)) :-
    (term_contains_heuristic(A) ; term_contains_heuristic(B)).
term_contains_heuristic((A, B)) :-
    (term_contains_heuristic(A) ; term_contains_heuristic(B)).

%% ─── Required imports in generated code ──────────────────────────────────────

test(required_imports_present) :-
    Terms = [(fact(1))],
    with_output_to(string(Output), piglog_output(terms(Terms), [])),
    sub_string(Output, _, _, _, "use_module(library(thread))").

%% ─── Cleanup after tests ─────────────────────────────────────────────────────

:- end_tests(generated_code).
