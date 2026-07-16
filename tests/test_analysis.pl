%% test_analysis.pl
%% Analysis tests for Piglog 2.

:- use_module(library(plunit)).
:- use_module('../piglog2_analyser').

:- begin_tests(analyser).

%% ─── Test: Flatten conjunction ───────────────────────────────────────────────

test(flatten_simple) :-
    flatten_conjunction((a, b, c), Goals),
    Goals = [a, b, c].

test(flatten_nested) :-
    flatten_conjunction(((a, b), c), Goals),
    Goals = [a, b, c].

test(flatten_single) :-
    flatten_conjunction(a, Goals),
    Goals = [a].

test(flatten_true) :-
    flatten_conjunction(true, Goals),
    Goals = [].

test(flatten_with_true) :-
    flatten_conjunction((a, true, b), Goals),
    Goals = [a, b].

%% ─── Test: Variable analysis ─────────────────────────────────────────────────

test(variable_analysis_simple) :-
    analyse_body((a(X, Y), b(Y, Z)), [X], Sections),
    Sections = [section([a(X,Y)], _, [Y], _), section([b(Y,Z)], _, [Z], _)].

test(variable_analysis_independent) :-
    analyse_body((f(X, A), g(X, B)), [X], Sections),
    length(Sections, 2),
    Sections = [section([f(X,A)], _, [A], _), section([g(X,B)], _, [B], _)].

%% ─── Test: Section independence ──────────────────────────────────────────────

test(sections_independent_no_shared_outputs) :-
    S1 = section([f(X, A)], [X], [A], meta(0, false)),
    S2 = section([g(X, B)], [X], [B], meta(1, false)),
    sections_independent(S1, S2).

test(sections_dependent_chained) :-
    S1 = section([a(X, A)], [X], [A], meta(0, false)),
    S2 = section([b(A, B)], [A], [B], meta(1, false)),
    \+ sections_independent(S1, S2).

test(sections_cut_boundary) :-
    S1 = section([a], [], [], meta(0, true)),  % has cut
    S2 = section([b], [], [], meta(1, false)),
    \+ sections_independent(S1, S2).

test(sections_shared_output_rejected) :-
    S1 = section([f(X)], [], [X], meta(0, false)),
    S2 = section([g(X)], [], [X], meta(1, false)),
    \+ sections_independent(S1, S2).

%% ─── Test: Independent groups found ─────────────────────────────────────────

test(find_independent_groups_basic) :-
    S1 = section([f(X, A)], [X], [A], meta(0, false)),
    S2 = section([g(X, B)], [X], [B], meta(1, false)),
    S3 = section([h(A, B, Z)], [A, B], [Z], meta(2, false)),
    find_independent_groups([S1, S2, S3], Groups),
    Groups \= [].

test(find_no_groups_sequential) :-
    S1 = section([a(X, A)], [X], [A], meta(0, false)),
    S2 = section([b(A, B)], [A], [B], meta(1, false)),
    find_independent_groups([S1, S2], Groups),
    Groups = [].

:- end_tests(analyser).
