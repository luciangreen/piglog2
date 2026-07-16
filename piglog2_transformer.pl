%% piglog2_transformer.pl
%% Source transformation for Piglog 2.
%%
%% Transforms analysed clauses by inserting SWI-Prolog concurrency constructs
%% where appropriate. All decisions are made here at conversion time.
%%
%% NOTE: Variable identity must be preserved throughout transformation.
%% findall/3 creates fresh variable copies; we avoid it for anything
%% that involves actual clause terms with shared variables.

:- module(piglog2_transformer, [
    transform_terms/3,
    transform_clause/5,
    generate_unique_name/3,
    try_transform_maplist/4
]).

:- use_module(piglog2_analyser).
:- use_module(piglog2_safety).
:- use_module(piglog2_estimator).
:- use_module(piglog2_config).

%% ─── Counter for unique names ─────────────────────────────────────────────────

:- dynamic piglog2_name_counter/1.
piglog2_name_counter(0).

next_counter(N) :-
    retract(piglog2_name_counter(N)),
    N1 is N + 1,
    assertz(piglog2_name_counter(N1)).

generate_unique_name(Prefix, Base, Name) :-
    next_counter(N),
    atomic_list_concat([Prefix, Base, '_', N], Name).

%% ─── Main transformation entry point ─────────────────────────────────────────

transform_terms(Terms, Options, transform_result(Generated, Helpers, Reports)) :-
    retractall(piglog2_name_counter(_)),
    assertz(piglog2_name_counter(0)),
    process_source_directives(Terms, Options),
    %% Generated0 contains transformed clauses WITHOUT helpers
    %% Helpers are returned separately for the caller to handle
    transform_terms_list(Terms, Options, Generated, Helpers, Reports).

process_source_directives([], _).
process_source_directives([(:- Directive)|Rest], Options) :-
    !,
    handle_source_directive(Directive),
    process_source_directives(Rest, Options).
process_source_directives([_|Rest], Options) :-
    process_source_directives(Rest, Options).

handle_source_directive(piglog_cost(Indicator, Cost)) :-
    !, declare_cost(Indicator, Cost).
handle_source_directive(piglog_long(Indicator)) :-
    !, declare_long(Indicator).
handle_source_directive(piglog_thread_safe(Indicator)) :-
    !, declare_thread_safe(Indicator).
handle_source_directive(piglog_thread_unsafe(Indicator)) :-
    !, declare_thread_unsafe(Indicator).
handle_source_directive(piglog_deterministic(Indicator)) :-
    !, declare_deterministic(Indicator).
handle_source_directive(piglog_minimum_concurrent_time(T)) :-
    !, piglog2_set_config(minimum_concurrent_time, T).
handle_source_directive(piglog_max_threads(N)) :-
    !, piglog2_set_config(maximum_threads, N).
handle_source_directive(_).

transform_terms_list([], _, [], [], []).
transform_terms_list([Term|Rest], Options,
                     [GenTerm|GenRest], Helpers, [Report|Reports]) :-
    transform_single_term(Term, Options, GenTerm, TermHelpers, Report),
    !,
    transform_terms_list(Rest, Options, GenRest, RestHelpers, Reports),
    append(TermHelpers, RestHelpers, Helpers).
transform_terms_list([Term|Rest], Options, [Term|GenRest], Helpers, Reports) :-
    transform_terms_list(Rest, Options, GenRest, Helpers, Reports).

transform_single_term((:- Directive), _Options, (:- Directive), [], report_directive(Directive)) :- !.
transform_single_term((Head :- Body), Options, GeneratedClause, Helpers, Report) :-
    !,
    transform_clause((Head :- Body), Options, GeneratedClause, Helpers, Report).
transform_single_term(Head, _Options, Head, [], report_fact(Head)) :-
    callable(Head).

%% ─── Clause transformation ────────────────────────────────────────────────────

transform_clause((Head :- Body), Options, (Head :- NewBody), Helpers, Report) :-
    functor(Head, Name, Arity),
    Indicator = Name/Arity,
    term_variables(Head, HeadVars),
    analyse_body(Body, HeadVars, Sections),
    try_concurrent_transform(Sections, Options, Head, NewBody, Helpers, GroupReports),
    (GroupReports = [] ->
        Report = report(Indicator, retained_sequential_all, [])
    ;
        Report = report(Indicator, converted, GroupReports)
    ).

%% try_concurrent_transform(+Sections, +Options, +Head,
%%                           -NewBody, -Helpers, -Reports)
%%
%% KEY DESIGN: We work with section indices to avoid variable copying.
%% Sections contain real Prolog variables from the clause - never copy them.

try_concurrent_transform(Sections, Options, Head, NewBody, Helpers, Reports) :-
    length(Sections, N),
    N >= 2,
    !,
    %% Find independent index pairs - safe to use findall (only indices)
    N1 is N - 1,
    findall(I-J,
            (between(0, N1, I),
             I1 is I + 1,
             between(I1, N1, J),
             nth0(I, Sections, Si),
             nth0(J, Sections, Sj),
             section_pair_independent(Si, Sj, Sections, I, J)),
            Pairs),
    (Pairs = [] ->
        Helpers = [],
        Reports = [],
        sections_to_body(Sections, NewBody)
    ;
        %% Choose best pair/group to convert
        find_best_group(Pairs, Sections, Options, BestIndices),
        (BestIndices = [] ->
            sections_to_body(Sections, NewBody),
            Helpers = [],
            Reports = []
        ;
            %% Apply the transformation with original variable-bearing sections
            apply_transformation(BestIndices, Sections, Options, Head,
                                 NewBody, Helpers, Reports)
        )
    ).
try_concurrent_transform(Sections, _Options, _Head, NewBody, [], []) :-
    sections_to_body(Sections, NewBody).

%% ─── Independence check ──────────────────────────────────────────────────────

section_pair_independent(Si, Sj, AllSections, I, J) :-
    Si = section(_, _, _, meta(_, false)),
    Sj = section(_, _, _, meta(_, false)),
    \+ any_cut_between(AllSections, I, J),
    \+ section_transitively_depends(AllSections, J, I),
    \+ section_transitively_depends(AllSections, I, J).

%% section_transitively_depends(+Sections, +DepIdx, +BaseIdx)
%% True if section DepIdx transitively depends on section BaseIdx.

section_transitively_depends(Sections, DepIdx, BaseIdx) :-
    section_trans_dep_(Sections, DepIdx, BaseIdx, []).

section_trans_dep_(Sections, DepIdx, BaseIdx, _) :-
    DepIdx \= BaseIdx,
    nth0(DepIdx, Sections, section(_, Inputs_dep, _, _)),
    nth0(BaseIdx, Sections, section(_, _, Outputs_base, _)),
    vars_overlap(Outputs_base, Inputs_dep).
section_trans_dep_(Sections, DepIdx, BaseIdx, Visited) :-
    DepIdx \= BaseIdx,
    \+ member(DepIdx, Visited),
    nth0(DepIdx, Sections, section(_, Inputs_dep, _, _)),
    length(Sections, N), N1 is N - 1,
    between(0, N1, Mid),
    Mid \= DepIdx, Mid \= BaseIdx,
    nth0(Mid, Sections, section(_, _, Outputs_mid, _)),
    vars_overlap(Outputs_mid, Inputs_dep),
    section_trans_dep_(Sections, Mid, BaseIdx, [DepIdx|Visited]).

any_cut_between(Sections, I, J) :-
    I < J,
    I1 is I + 1,
    J1 is J - 1,
    I1 =< J1,
    between(I1, J1, K),
    nth0(K, Sections, section(_, _, _, meta(_, true))),
    !.

vars_overlap(Vs1, Vs2) :-
    member(V1, Vs1),
    var_member(V1, Vs2),
    !.

var_member(V, [H|_]) :- V == H, !.
var_member(V, [_|T]) :- var_member(V, T).

%% ─── Group selection ─────────────────────────────────────────────────────────

%% find_best_group(+Pairs, +Sections, +Options, -Indices)
%% Choose the best group of indices to convert concurrently.
%% Returns [] if no group passes the threshold.

find_best_group(Pairs, Sections, Options, BestIndices) :-
    %% Build maximal cliques from pairs (every member must be pairwise independent)
    build_cliques_from_pairs(Pairs, Cliques),
    %% Evaluate each clique: check safety, cost
    find_best_index_set(Cliques, Sections, Options, BestIndices).

%% build_cliques_from_pairs(+Pairs, -Cliques)
%% Build maximal cliques where every pair of indices appears in Pairs.

build_cliques_from_pairs(Pairs, Cliques) :-
    pairs_to_sets(Pairs, [], RawSets),
    maplist([S, C]>>(prune_to_clique(S, Pairs, C)), RawSets, AllCliques),
    include([S]>>(length(S, L), L >= 2), AllCliques, Cliques).

prune_to_clique(Set, Pairs, Clique) :-
    prune_to_clique_(Set, Pairs, Set, Clique).

prune_to_clique_([], _, Acc, Acc).
prune_to_clique_([I|Rest], Pairs, Acc, Clique) :-
    delete(Acc, I, Others),
    (all_pairs_present(I, Others, Pairs) ->
        prune_to_clique_(Rest, Pairs, Acc, Clique)
    ;
        delete(Acc, I, NewAcc),
        prune_to_clique_(Rest, Pairs, NewAcc, Clique)
    ).

all_pairs_present(_, [], _) :- !.
all_pairs_present(I, [J|Rest], Pairs) :-
    (member(I-J, Pairs) ; member(J-I, Pairs)),
    !,
    all_pairs_present(I, Rest, Pairs).

pairs_to_sets([], Acc, Acc).
pairs_to_sets([I-J|Rest], Acc, Result) :-
    (find_set_with(I, Acc, Set, Others) ->
        (find_set_with(J, Others, Set2, Others2) ->
            union_sets(Set, Set2, Merged),
            NewAcc = [Merged|Others2]
        ;
            add_to_set(J, Set, NewSet),
            NewAcc = [NewSet|Others]
        )
    ;
        (find_set_with(J, Acc, Set, Others) ->
            add_to_set(I, Set, NewSet),
            NewAcc = [NewSet|Others]
        ;
            NewAcc = [[I,J]|Acc]
        )
    ),
    pairs_to_sets(Rest, NewAcc, Result).

find_set_with(X, [S|Rest], S, Rest) :- member(X, S), !.
find_set_with(X, [S|Rest], Found, [S|Others]) :-
    find_set_with(X, Rest, Found, Others).

add_to_set(X, S, S) :- member(X, S), !.
add_to_set(X, S, [X|S]).

union_sets(A, B, C) :- append(A, B, AB), sort(AB, C).

find_best_index_set([], _, _, []).
find_best_index_set([Set|Rest], Sections, Options, Best) :-
    sort(Set, SortedSet),
    %% Filter to sections that individually exceed the cost threshold
    include({Sections, Options}/[I]>>(
        nth0(I, Sections, S),
        estimate_section_cost(S, Options, C),
        threshold_exceeded(C, Options)),
        SortedSet, CostlySet),
    (length(CostlySet, CL), CL >= 2 ->
        maplist(nth0_section(Sections), CostlySet, GSections),
        (maplist(section_safe_for_concurrency, GSections) ->
            Best = CostlySet
        ;
            find_best_index_set(Rest, Sections, Options, Best)
        )
    ;
        find_best_index_set(Rest, Sections, Options, Best)
    ).

nth0_section(Sections, I, S) :- nth0(I, Sections, S).

estimate_section_cost_opt(Options, Section, Cost) :-
    estimate_section_cost(Section, Options, Cost).

%% ─── Applying the transformation ─────────────────────────────────────────────

apply_transformation(Indices, AllSections, Options, Head,
                     NewBody, Helpers, [Report]) :-
    %% Get sections by index (preserves original variables)
    maplist(nth0_section(AllSections), Indices, GSections),
    option_max_threads(Options, MaxThreads),
    length(Indices, NWorkers),
    ThreadCount is min(NWorkers, MaxThreads),
    %% Build costs for report
    maplist(estimate_section_cost_opt(Options), GSections, Costs),
    sum_list(Costs, TotalSeq),
    max_list(Costs, MaxCost),
    get_concurrency_overhead(Overhead),
    EstConc is MaxCost + Overhead,
    EstSaving is TotalSeq - EstConc,
    %% Use concurrent/3 - it correctly shares variable bindings with the caller.
    %% Section independence already ensures no shared OUTPUT variables between goals.
    %% Input variables and output-to-continuation variables work correctly.
    maplist(section_to_goal, GSections, Goals),
    ConcGoal = concurrent(ThreadCount, Goals, []),
    Helpers = [],
    ConstructType = concurrent3,
    %% Rebuild body replacing grouped sections with ConcGoal
    rebuild_body_sequential(AllSections, Indices, ConcGoal, NewBody),
    %% Build report
    functor(Head, HName, HArity),
    Report = group_report(
        predicate(HName/HArity),
        sections(Indices),
        estimated_sequential(TotalSeq),
        estimated_concurrent(EstConc),
        estimated_saving(EstSaving),
        construct(ConstructType),
        decision(converted_concurrent)
    ).

collect_section_outputs([], []).
collect_section_outputs([section(_, _, Outs, _)|Rest], All) :-
    collect_section_outputs(Rest, RestOuts),
    append(Outs, RestOuts, All).

collect_continuation_needs(Indices, AllSections, Inputs) :-
    length(AllSections, N),
    N1 is N - 1,
    (Indices = [] ->
        Inputs = []
    ;
        max_list(Indices, MaxIdx),
        (MaxIdx < N1 ->
            After is MaxIdx + 1,
            %% Do NOT use findall here - it would copy variables!
            %% Instead iterate directly to preserve variable identity
            collect_cont_inputs_direct(AllSections, After, N1, 0, [], Inputs)
        ;
            Inputs = []
        )
    ).

%% collect_cont_inputs_direct(+Sections, +From, +To, +I, +Acc, -Inputs)
%% Accumulates input variables from sections at indices From..To.
%% Direct iteration preserves original variable identity.

collect_cont_inputs_direct([], _, _, _, Acc, Acc).
collect_cont_inputs_direct([S|Rest], From, To, I, Acc, Inputs) :-
    I1 is I + 1,
    (I >= From, I =< To ->
        S = section(_, Ins, _, _),
        append(Acc, Ins, NewAcc),
        collect_cont_inputs_direct(Rest, From, To, I1, NewAcc, Inputs)
    ;
        collect_cont_inputs_direct(Rest, From, To, I1, Acc, Inputs)
    ).

needs_result_transport(Outputs, ContInputs) :-
    member(V, Outputs),
    var_member(V, ContInputs),
    !.

section_to_goal(section(Goals, _, _, _), Goal) :-
    goals_to_conjunction(Goals, Goal).

%% rebuild_body_sequential(+AllSections, +GroupIndices, +ConcGoal, -NewBody)
%%
%% Build new body:
%% - sections at first GroupIndex → ConcGoal
%% - sections at other GroupIndices → omitted
%% - all other sections → their goals
%%
%% IMPORTANT: We iterate directly, no findall, preserving variable identity.

rebuild_body_sequential(AllSections, GroupIndices, ConcGoal, NewBody) :-
    sort(GroupIndices, SortedIdx),
    SortedIdx = [FirstIdx|_],
    collect_body_parts(AllSections, 0, FirstIdx, SortedIdx, ConcGoal, Parts),
    parts_to_conjunction(Parts, NewBody).

collect_body_parts([], _, _, _, _, []).
collect_body_parts([S|Rest], I, FirstIdx, SortedIdx, ConcGoal, Parts) :-
    I1 is I + 1,
    (I =:= FirstIdx ->
        Parts = [ConcGoal | RestParts],
        collect_body_parts(Rest, I1, FirstIdx, SortedIdx, ConcGoal, RestParts)
    ;
        (member(I, SortedIdx) ->
            %% Part of group but not first: skip
            collect_body_parts(Rest, I1, FirstIdx, SortedIdx, ConcGoal, Parts)
        ;
            %% Not in group: include sequentially
            S = section(Goals, _, _, _),
            goals_to_conjunction(Goals, Part),
            Parts = [Part | RestParts],
            collect_body_parts(Rest, I1, FirstIdx, SortedIdx, ConcGoal, RestParts)
        )
    ).

%% sections_to_body(+Sections, -Body)

sections_to_body([], true).
sections_to_body(Sections, Body) :-
    maplist([section(Goals,_,_,_), G]>>(goals_to_conjunction(Goals, G)),
            Sections, Parts),
    parts_to_conjunction(Parts, Body).

%% ─── Thread worker transformation ────────────────────────────────────────────

transform_with_workers(GSections, _Indices, _AllSections, Options, Head,
                        _ThreadCount, ConcGoal, Helpers) :-
    functor(Head, HName, HArity),
    length(GSections, NWorkers),
    numlist(1, NWorkers, WorkerNums),
    %% Generate worker predicates - preserve variables in Goals
    maplist(make_worker_predicate(HName, HArity), WorkerNums, GSections,
            WorkerCalls, WorkerClauses),
    Helpers = WorkerClauses,
    %% Build the concurrent goal using thread_create/thread_join
    option_max_threads(Options, MaxThreads),
    MaxUsed is min(NWorkers, MaxThreads),
    build_parallel_call(WorkerCalls, MaxUsed, ConcGoal).

make_worker_predicate(HName, HArity, Num, section(Goals, Inputs, Outputs, _),
                       WorkerCall, WorkerClause) :-
    atomic_list_concat(['$piglog2_worker_', HName, '_', HArity, '_', Num],
                       WorkerName),
    append(Inputs, Outputs, AllArgs),
    WorkerHead =.. [WorkerName | AllArgs],
    goals_to_conjunction(Goals, WorkerBody),
    WorkerClause = (WorkerHead :- WorkerBody),
    %% The call to the worker uses the same variables (shared!)
    WorkerCall =.. [WorkerName | AllArgs].

%% build_parallel_call(+WorkerCalls, +MaxThreads, -Goal)
%% Build a goal that runs workers concurrently using thread_create/join.
%% The workers share variables with the outer clause - they ARE the computation.
%%
%% For output-producing workers, we use the pattern:
%%   thread_create(Worker1, T1, []),
%%   thread_create(Worker2, T2, []),
%%   thread_join(T1, true),
%%   thread_join(T2, true)
%%
%% This is valid because the worker calls SHARE variables with the outer goal.
%% SWI-Prolog threads can share variables via their goal term.

build_parallel_call(WorkerCalls, _MaxThreads, Goal) :-
    length(WorkerCalls, N),
    length(ThreadVars, N),
    maplist(make_create, WorkerCalls, ThreadVars, Creates),
    maplist(make_join, ThreadVars, Joins),
    append(Creates, Joins, AllGoals),
    goals_to_conjunction(AllGoals, Goal).

make_create(Call, TVar, thread_create(Call, TVar, [])).
make_join(TVar, thread_join(TVar, true)).

%% ─── Maplist transformation ──────────────────────────────────────────────────

try_transform_maplist(maplist(Pred, List), Options, NewGoal, Decision) :-
    !,
    estimate_goal_cost(Pred, Options, Cost),
    (threshold_exceeded(Cost, Options) ->
        NewGoal = concurrent_maplist(Pred, List),
        Decision = converted_concurrent_maplist
    ;
        NewGoal = maplist(Pred, List),
        Decision = retained_sequential_short
    ).
try_transform_maplist(maplist(Pred, List, Outputs), Options, NewGoal, Decision) :-
    !,
    estimate_goal_cost(Pred, Options, Cost),
    (threshold_exceeded(Cost, Options) ->
        NewGoal = concurrent_maplist(Pred, List, Outputs),
        Decision = converted_concurrent_maplist
    ;
        NewGoal = maplist(Pred, List, Outputs),
        Decision = retained_sequential_short
    ).

%% ─── Utility ─────────────────────────────────────────────────────────────────

goals_to_conjunction([], true).
goals_to_conjunction([G], G) :- !.
goals_to_conjunction([G|Rest], (G, RestConj)) :-
    goals_to_conjunction(Rest, RestConj).

parts_to_conjunction([], true).
parts_to_conjunction([P], P) :- !.
parts_to_conjunction([P|Rest], (P, RestConj)) :-
    parts_to_conjunction(Rest, RestConj).

sum_list([], 0).
sum_list([H|T], Sum) :-
    sum_list(T, Rest),
    Sum is H + Rest.

option_max_threads(Options, N) :-
    (member(maximum_threads(N), Options) -> true ;
     piglog2_config(maximum_threads, N)).
