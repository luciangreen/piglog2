%% piglog2_analyser.pl
%% Clause-body analysis for Piglog 2.
%%
%% Stages:
%%   1. Flatten conjunction into a list of calls
%%   2. Identify variables produced and consumed by each call
%%   3. Build dependency graph
%%   4. Form executable sections (groups of dependent calls)
%%   5. Identify independent section pairs / groups

:- module(piglog2_analyser, [
    analyse_clause/3,
    analyse_body/3,
    flatten_conjunction/2,
    build_sections/3,
    find_independent_groups/2,
    vars_produced_by/3,
    vars_consumed_by/3,
    sections_independent/2
]).

%% analyse_clause(+Clause, +Options, -Analysis)
%%
%% Analysis = clause_analysis(Head, Sections, IndependentGroups)

analyse_clause((Head :- Body), Options, Analysis) :-
    !,
    term_variables(Head, HeadVars),
    analyse_body(Body, HeadVars, Sections),
    find_independent_groups(Sections, Groups),
    Analysis = clause_analysis(Head, Sections, Groups, Options).
analyse_clause(Head, Options, Analysis) :-
    callable(Head),
    Analysis = clause_analysis(Head, [], [], Options).

%% analyse_body(+Body, +HeadVars, -Sections)
%%
%% Flatten body and build sections with variable flow information.
%% A section is section(Goals, Inputs, Outputs, CutBoundary)

analyse_body(Body, HeadVars, Sections) :-
    flatten_conjunction(Body, Goals),
    build_sections(Goals, HeadVars, Sections).

%% flatten_conjunction(+Body, -Goals)
%%
%% Flatten (A, B) into a list, preserving structure of other goals.
%% Uses a difference-list helper so that right-nested conjunctions
%% (the common Prolog form) are processed via tail-call optimisation,
%% avoiding stack overflow on large clause bodies.

flatten_conjunction(Body, Goals) :-
    flatten_conj(Body, Goals, []).

flatten_conj((A, B), Goals, Tail) :-
    !,
    flatten_conj(A, Goals, Mid),
    flatten_conj(B, Mid, Tail).
flatten_conj(true, Tail, Tail) :- !.
flatten_conj(Goal, [Goal|Tail], Tail).

%% build_sections(+Goals, +AvailableVars, -Sections)
%%
%% For each goal, compute:
%%   - which variables it needs (already available)
%%   - which variables it produces (first occurrence)
%%   - whether it contains a cut
%%
%% A section is: section(Goals, Inputs, Outputs, Meta)
%% where Meta includes: cut_boundary(Bool), index(N)

build_sections(Goals, InitialVars, Sections) :-
    build_sections(Goals, InitialVars, 0, Sections).

build_sections([], _, _, []).
build_sections([Goal|Rest], Available, Idx, [Section|Sections]) :-
    NextIdx is Idx + 1,
    term_variables(Goal, GoalVars),
    partition_vars(GoalVars, Available, Inputs, NewOutputs),
    append(Available, NewOutputs, NewAvailable),
    (Goal == (!) -> CutBoundary = true ; CutBoundary = false),
    Section = section([Goal], Inputs, NewOutputs, meta(Idx, CutBoundary)),
    build_sections(Rest, NewAvailable, NextIdx, Sections).

%% partition_vars(+Vars, +Available, -Inputs, -NewOutputs)
%%
%% Vars in Available → Inputs (already known)
%% Vars not in Available → NewOutputs (first occurrence → produced here)

partition_vars([], _, [], []).
partition_vars([V|Vs], Available, Inputs, Outputs) :-
    (var_member(V, Available) ->
        Inputs = [V|RestInputs],
        Outputs = RestOutputs
    ;
        Inputs = RestInputs,
        Outputs = [V|RestOutputs]
    ),
    partition_vars(Vs, Available, RestInputs, RestOutputs).

%% var_member(+Var, +List)
%% Check if a variable (by identity) is in a list.

var_member(V, [H|_]) :- V == H, !.
var_member(V, [_|T]) :- var_member(V, T).

%% vars_produced_by(+Section, +All, -Produced)
%% Get all variables produced (output) by a section.

vars_produced_by(section(_, _, Outputs, _), _, Outputs).

%% vars_consumed_by(+Section, +All, -Consumed)
%% Get all variables consumed (input) by a section.

vars_consumed_by(section(_, Inputs, _, _), _, Inputs).

%% sections_independent(+Section1, +Section2)
%%
%% Two sections are independent if:
%%  1. Section1 does not produce variables consumed by Section2
%%  2. Section2 does not produce variables consumed by Section1
%%  3. Neither has a cut boundary between them

sections_independent(S1, S2) :-
    S1 = section(_, _, Outputs1, meta(_, Cut1)),
    S2 = section(_, Inputs2, Outputs2, meta(_, Cut2)),
    Cut1 = false,
    Cut2 = false,
    \+ vars_overlap(Outputs1, Inputs2),
    \+ vars_overlap(Outputs2, section_inputs(S1)),
    \+ vars_overlap(Outputs1, Outputs2).

section_inputs(section(_, Inputs, _, _), Inputs).

vars_overlap(Vs1, Vs2) :-
    member(V1, Vs1),
    var_member(V1, Vs2),
    !.

%% find_independent_groups(+Sections, -Groups)
%%
%% Find groups of mutually independent sections.
%% Returns a list of groups: group(SectionIndices, SequentialContinuations)

find_independent_groups(Sections, Groups) :-
    length(Sections, N),
    N1 is N - 1,
    numlist(0, N1, Indices),
    find_concurrent_candidates(Sections, Indices, Groups).

find_concurrent_candidates(Sections, _Indices, Groups) :-
    find_all_independent_pairs(Sections, Pairs),
    form_groups_from_pairs(Pairs, Sections, Groups).

find_all_independent_pairs(Sections, Pairs) :-
    length(Sections, N),
    N1 is N - 1,
    findall(pair(I,J),
            (between(0, N1, I),
             I1 is I + 1,
             between(I1, N1, J),
             nth0(I, Sections, Si),
             nth0(J, Sections, Sj),
             sections_are_independent(Si, Sj, Sections, I, J)),
            Pairs).

%% sections_are_independent(+Si, +Sj, +AllSections, +I, +J)
%% Si at index I and Sj at index J are independent if:
%% - No direct or transitive data dependency between them
%% - No cut boundary between them

sections_are_independent(Si, Sj, AllSections, I, J) :-
    Si = section(_, _, _, meta(_, Cut_i)),
    Sj = section(_, _, _, meta(_, Cut_j)),
    Cut_i = false,
    Cut_j = false,
    \+ cut_between(AllSections, I, J),
    \+ section_depends_on(AllSections, J, I),
    \+ section_depends_on(AllSections, I, J).

%% section_depends_on(+Sections, +DepIdx, +BaseIdx)
%% True if section at DepIdx transitively depends on section at BaseIdx.

section_depends_on(Sections, DepIdx, BaseIdx) :-
    section_depends_on_(Sections, DepIdx, BaseIdx, []).

section_depends_on_(Sections, DepIdx, BaseIdx, _Visited) :-
    DepIdx \= BaseIdx,
    nth0(DepIdx, Sections, section(_, Inputs_dep, _, _)),
    nth0(BaseIdx, Sections, section(_, _, Outputs_base, _)),
    vars_overlap(Outputs_base, Inputs_dep).
section_depends_on_(Sections, DepIdx, BaseIdx, Visited) :-
    DepIdx \= BaseIdx,
    \+ member(DepIdx, Visited),
    nth0(DepIdx, Sections, section(_, Inputs_dep, _, _)),
    length(Sections, N),
    N1 is N - 1,
    between(0, N1, Mid),
    Mid \= DepIdx,
    Mid \= BaseIdx,
    nth0(Mid, Sections, section(_, _, Outputs_mid, _)),
    vars_overlap(Outputs_mid, Inputs_dep),
    section_depends_on_(Sections, Mid, BaseIdx, [DepIdx|Visited]).

section_all_inputs(section(_, Inputs, _, _), Inputs).

cut_between(Sections, I, J) :-
    I < J,
    I1 is I + 1,
    J1 is J - 1,
    between(I1, J1, K),
    nth0(K, Sections, section(_, _, _, meta(_, true))),
    !.

%% form_groups_from_pairs(+Pairs, +Sections, -Groups)
%% Cluster independent pairs into maximal groups.

form_groups_from_pairs([], _, []).
form_groups_from_pairs(Pairs, Sections, Groups) :-
    Pairs \= [],
    form_connected_groups(Pairs, Sections, Groups).

form_connected_groups(Pairs, Sections, Groups) :-
    pairs_to_sets(Pairs, [], Sets),
    sets_to_groups(Sets, Sections, Groups).

pairs_to_sets([], Acc, Acc).
pairs_to_sets([pair(I,J)|Rest], Acc, Result) :-
    (find_set_containing(I, Acc, Set, OtherSets) ->
        (find_set_containing(J, OtherSets, Set2, OtherSets2) ->
            union(Set, Set2, MergedSet),
            NewAcc = [MergedSet|OtherSets2]
        ;
            add_to_set(J, Set, NewSet),
            NewAcc = [NewSet|OtherSets]
        )
    ;
        (find_set_containing(J, Acc, Set, OtherSets) ->
            add_to_set(I, Set, NewSet),
            NewAcc = [NewSet|OtherSets]
        ;
            NewAcc = [[I,J]|Acc]
        )
    ),
    pairs_to_sets(Rest, NewAcc, Result).

find_set_containing(X, [Set|Rest], Set, Rest) :-
    member(X, Set),
    !.
find_set_containing(X, [Set|Rest], FoundSet, [Set|OtherSets]) :-
    find_set_containing(X, Rest, FoundSet, OtherSets).

add_to_set(X, Set, [X|Set]) :-
    \+ member(X, Set),
    !.
add_to_set(_, Set, Set).

union(A, B, C) :-
    append(A, B, AB),
    sort(AB, C).

sets_to_groups([], _, []).
sets_to_groups([Set|Sets], Sections, [Group|Groups]) :-
    length(Set, Len),
    Len >= 2,
    !,
    maplist(nth0_sections(Sections), Set, GroupSections),
    Group = concurrent_group(Set, GroupSections),
    sets_to_groups(Sets, Sections, Groups).
sets_to_groups([_|Sets], Sections, Groups) :-
    sets_to_groups(Sets, Sections, Groups).

nth0_sections(Sections, I, S) :- nth0(I, Sections, S).

%% merge_dependent_sections(+Sections, -MergedSections)
%%
%% Merge consecutive dependent sections into longer chains.
%% This enables long-section grouping (Stage 7).

merge_dependent_sections([], []).
merge_dependent_sections([S], [S]).
merge_dependent_sections([S1, S2 | Rest], Merged) :-
    sections_dependent(S1, S2),
    !,
    merge_two_sections(S1, S2, S12),
    merge_dependent_sections([S12|Rest], Merged).
merge_dependent_sections([S1|Rest], [S1|Merged]) :-
    merge_dependent_sections(Rest, Merged).

sections_dependent(S1, S2) :-
    S1 = section(_, _, Outputs1, _),
    S2 = section(_, Inputs2, _, _),
    vars_overlap(Outputs1, Inputs2).

merge_two_sections(section(G1, In1, Out1, meta(I1, Cut1)),
                   section(G2, In2, Out2, meta(_I2, Cut2)),
                   section(Goals, Inputs, Outputs, meta(I1, CutOut))) :-
    append(G1, G2, Goals),
    subtract_vars(In2, Out1, NewIn2),
    append(In1, NewIn2, Inputs),
    append(Out1, Out2, Outputs),
    (Cut1 = true ; Cut2 = true -> CutOut = true ; CutOut = false).

subtract_vars([], _, []).
subtract_vars([V|Vs], Remove, Result) :-
    (var_member(V, Remove) ->
        subtract_vars(Vs, Remove, Result)
    ;
        Result = [V|Rest],
        subtract_vars(Vs, Remove, Rest)
    ).
