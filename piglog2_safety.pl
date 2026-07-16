%% piglog2_safety.pl
%% Safety classification for Piglog 2.
%%
%% Classifies goals and sections as:
%%   - deterministic / semideterministic / nondeterministic / multi / unknown
%%   - effectful / pure
%%   - thread-safe / thread-unsafe / unknown_safety
%%   - cut_boundary

:- module(piglog2_safety, [
    classify_goal/2,
    goal_is_safe_for_concurrency/1,
    section_safe_for_concurrency/1,
    goal_has_side_effect/1,
    goal_is_thread_safe/1,
    goal_is_deterministic/1,
    declare_thread_safe/1,
    declare_thread_unsafe/1,
    declare_deterministic/1,
    declare_cost/2,
    declare_long/1,
    piglog_thread_safe/1,
    piglog_thread_unsafe/1,
    piglog_deterministic/1,
    piglog_cost/2,
    piglog_long/1,
    infer_thread_safe_in_module/3,
    %% Dynamic user declaration facts (exported for other modules)
    piglog_user_thread_safe/1,
    piglog_user_thread_unsafe/1,
    piglog_user_deterministic/1,
    piglog_user_cost/2,
    piglog_user_long/1
]).

%% ─── User declarations (dynamic) ─────────────────────────────────────────────

:- dynamic piglog_user_thread_safe/1.
:- dynamic piglog_user_thread_unsafe/1.
:- dynamic piglog_user_deterministic/1.
:- dynamic piglog_user_cost/2.
:- dynamic piglog_user_long/1.

declare_thread_safe(Indicator)  :- retractall(piglog_user_thread_safe(Indicator)),  assertz(piglog_user_thread_safe(Indicator)).
declare_thread_unsafe(Indicator):- retractall(piglog_user_thread_unsafe(Indicator)),assertz(piglog_user_thread_unsafe(Indicator)).
declare_deterministic(Indicator):- retractall(piglog_user_deterministic(Indicator)),assertz(piglog_user_deterministic(Indicator)).
declare_cost(Indicator, Cost)   :- retractall(piglog_user_cost(Indicator, _)),      assertz(piglog_user_cost(Indicator, Cost)).
declare_long(Indicator)         :- retractall(piglog_user_long(Indicator)),         assertz(piglog_user_long(Indicator)).

%% Public accessor predicates (for directive handling in source)
piglog_thread_safe(I)    :- declare_thread_safe(I).
piglog_thread_unsafe(I)  :- declare_thread_unsafe(I).
piglog_deterministic(I)  :- declare_deterministic(I).
piglog_cost(I, C)        :- declare_cost(I, C).
piglog_long(I)           :- declare_long(I).

%% ─── Known built-in safety database ─────────────────────────────────────────

%% Known deterministic predicates (Name/Arity)
known_deterministic(true/0).
known_deterministic(fail/0).
known_deterministic(false/0).
known_deterministic(!/0).
known_deterministic('='/2).
known_deterministic('\\='/2).
known_deterministic('=='/2).
known_deterministic('\\=='/2).
known_deterministic('is'/2).
known_deterministic('<'/2).
known_deterministic('>'/2).
known_deterministic('=<'/2).
known_deterministic('>='/2).
known_deterministic('=:='/2).
known_deterministic('=\\='/2).
known_deterministic(functor/3).
known_deterministic(arg/3).
known_deterministic('=..'/2).
known_deterministic(copy_term/2).
known_deterministic(length/2).
known_deterministic(append/3).
known_deterministic(last/2).
known_deterministic(nth0/3).
known_deterministic(nth1/3).
known_deterministic(succ/2).
known_deterministic(plus/3).
known_deterministic(atom/1).
known_deterministic(number/1).
known_deterministic(integer/1).
known_deterministic(float/1).
known_deterministic(compound/1).
known_deterministic(callable/1).
known_deterministic(is_list/1).
known_deterministic(var/1).
known_deterministic(nonvar/1).
known_deterministic(ground/1).
known_deterministic(atom_codes/2).
known_deterministic(atom_chars/2).
known_deterministic(atom_length/2).
known_deterministic(atom_concat/3).
known_deterministic(number_codes/2).
known_deterministic(number_chars/2).
known_deterministic(char_code/2).
known_deterministic(sub_atom/5).
known_deterministic(upcase_atom/2).
known_deterministic(downcase_atom/2).
known_deterministic(term_to_atom/2).
known_deterministic(with_output_to/2).
known_deterministic(format_atom/3).
known_deterministic(atomic_list_concat/2).
known_deterministic(atomic_list_concat/3).
known_deterministic(msort/2).
known_deterministic(sort/2).
known_deterministic(sort/4).
known_deterministic(maplist/2).
known_deterministic(maplist/3).
known_deterministic(maplist/4).
known_deterministic(include/3).
known_deterministic(exclude/3).
known_deterministic(foldl/4).
known_deterministic(foldl/5).
known_deterministic(aggregate_all/3).
known_deterministic(max_list/2).
known_deterministic(min_list/2).
known_deterministic(sum_list/2).
known_deterministic(numlist/3).
known_deterministic(max_member/2).
known_deterministic(min_member/2).
known_deterministic(pairs_keys_values/3).
known_deterministic(pairs_keys/2).
known_deterministic(pairs_values/2).
known_deterministic(succ_or_zero/2).
known_deterministic(string_concat/3).
known_deterministic(string_length/2).
known_deterministic(string_codes/2).
known_deterministic(string_chars/2).
known_deterministic(string_lower/2).
known_deterministic(string_upper/2).
known_deterministic(string_to_atom/2).
known_deterministic(number_string/2).
known_deterministic(term_string/2).

%% Known effectful predicates
known_effectful(write/1).
known_effectful(writeln/1).
known_effectful(write_term/2).
known_effectful(write_term/3).
known_effectful(print/1).
known_effectful(format/1).
known_effectful(format/2).
known_effectful(format/3).
known_effectful(nl/0).
known_effectful(tab/1).
known_effectful(put_char/1).
known_effectful(put_char/2).
known_effectful(char_code/2).
known_effectful(read/1).
known_effectful(read_term/2).
known_effectful(read_term/3).
known_effectful(get_char/1).
known_effectful(get_char/2).
known_effectful(peek_char/1).
known_effectful(open/3).
known_effectful(open/4).
known_effectful(close/1).
known_effectful(stream_property/2).
known_effectful(set_stream/2).
known_effectful(flush_output/0).
known_effectful(flush_output/1).
known_effectful(assert/1).
known_effectful(assertz/1).
known_effectful(asserta/1).
known_effectful(retract/1).
known_effectful(retractall/1).
known_effectful(abolish/1).
known_effectful(nb_setval/2).
known_effectful(nb_getval/2).
known_effectful(b_setval/2).
known_effectful(b_getval/2).
known_effectful(set_flag/2).
known_effectful(flag/3).
known_effectful(shell/1).
known_effectful(shell/2).
known_effectful(process_create/3).
known_effectful(sleep/1).
known_effectful(garbage_collect/0).
known_effectful(set_prolog_flag/2).

%% Known thread-unsafe predicates
known_thread_unsafe(assert/1).
known_thread_unsafe(assertz/1).
known_thread_unsafe(asserta/1).
known_thread_unsafe(retract/1).
known_thread_unsafe(retractall/1).
known_thread_unsafe(abolish/1).
known_thread_unsafe(nb_setval/2).
known_thread_unsafe(nb_getval/2).
known_thread_unsafe(set_flag/2).
known_thread_unsafe(flag/3).
known_thread_unsafe(shell/1).
known_thread_unsafe(shell/2).
known_thread_unsafe(process_create/3).
known_thread_unsafe(set_prolog_flag/2).

%% Known thread-safe predicates (pure computations)
known_thread_safe('is'/2).
known_thread_safe('='/2).
known_thread_safe('=='/2).
known_thread_safe('\\='/2).
known_thread_safe('\\=='/2).
known_thread_safe('<'/2).
known_thread_safe('>'/2).
known_thread_safe('=<'/2).
known_thread_safe('>='/2).
known_thread_safe('=:='/2).
known_thread_safe('=\\='/2).
known_thread_safe(functor/3).
known_thread_safe(arg/3).
known_thread_safe('=..'/2).
known_thread_safe(copy_term/2).
known_thread_safe(atom/1).
known_thread_safe(number/1).
known_thread_safe(integer/1).
known_thread_safe(float/1).
known_thread_safe(compound/1).
known_thread_safe(callable/1).
known_thread_safe(is_list/1).
known_thread_safe(var/1).
known_thread_safe(nonvar/1).
known_thread_safe(ground/1).
known_thread_safe(true/0).
known_thread_safe(fail/0).
known_thread_safe(false/0).
known_thread_safe(length/2).
known_thread_safe(append/3).
known_thread_safe(nth0/3).
known_thread_safe(nth1/3).
known_thread_safe(last/2).
known_thread_safe(member/2).
known_thread_safe(memberchk/2).
known_thread_safe(msort/2).
known_thread_safe(sort/2).
known_thread_safe(sort/4).
known_thread_safe(numlist/3).
known_thread_safe(max_list/2).
known_thread_safe(min_list/2).
known_thread_safe(sum_list/2).
known_thread_safe(atom_codes/2).
known_thread_safe(atom_chars/2).
known_thread_safe(atom_length/2).
known_thread_safe(atom_concat/3).
known_thread_safe(number_codes/2).
known_thread_safe(number_chars/2).
known_thread_safe(char_code/2).
known_thread_safe(atom_number/2).
known_thread_safe(sub_atom/5).
known_thread_safe(upcase_atom/2).
known_thread_safe(downcase_atom/2).
known_thread_safe(term_to_atom/2).
known_thread_safe(atomic_list_concat/2).
known_thread_safe(atomic_list_concat/3).
known_thread_safe(succ/2).
known_thread_safe(plus/3).
known_thread_safe(pairs_keys_values/3).
known_thread_safe(pairs_keys/2).
known_thread_safe(pairs_values/2).
known_thread_safe(foldl/4).
known_thread_safe(foldl/5).
known_thread_safe(maplist/2).
known_thread_safe(maplist/3).
known_thread_safe(maplist/4).
known_thread_safe(include/3).
known_thread_safe(exclude/3).
known_thread_safe(aggregate_all/3).
known_thread_safe(string_concat/3).
known_thread_safe(string_length/2).
known_thread_safe(string_codes/2).
known_thread_safe(string_chars/2).
known_thread_safe(number_string/2).
known_thread_safe(term_string/2).
known_thread_safe(string_to_atom/2).
known_thread_safe(with_output_to/2).
known_thread_safe(format_atom/3).

%% ─── Classification predicates ────────────────────────────────────────────────

%% classify_goal(+Goal, -Classification)
%% Returns a list of properties.

classify_goal(Goal, Classification) :-
    (callable(Goal) -> functor(Goal, Name, Arity) ; Name = '?', Arity = 0),
    Indicator = Name/Arity,
    findall(P, goal_property(Goal, Indicator, P), Props),
    sort(Props, Classification).

goal_property(_, _, cut_boundary) :-
    fail.  % handled separately via Goal == (!)
goal_property(Goal, _, cut_boundary) :-
    Goal == (!).
goal_property(_, Indicator, deterministic) :-
    (known_deterministic(Indicator) ; piglog_user_deterministic(Indicator)), !.
goal_property(_, Indicator, effectful) :-
    (known_effectful(Indicator)), !.
goal_property(_, Indicator, thread_safe) :-
    (known_thread_safe(Indicator) ; piglog_user_thread_safe(Indicator)),
    \+ known_thread_unsafe(Indicator),
    \+ piglog_user_thread_unsafe(Indicator), !.
goal_property(_, Indicator, thread_unsafe) :-
    (known_thread_unsafe(Indicator) ; piglog_user_thread_unsafe(Indicator)), !.
goal_property(_, _, pure) :-
    fail.

%% goal_has_side_effect(+Goal)

goal_has_side_effect(Goal) :-
    callable(Goal),
    functor(Goal, Name, Arity),
    (known_effectful(Name/Arity) ; piglog_user_thread_unsafe(Name/Arity)).

%% goal_is_thread_safe(+Goal)

goal_is_thread_safe(Goal) :-
    callable(Goal),
    functor(Goal, Name, Arity),
    Indicator = Name/Arity,
    \+ known_thread_unsafe(Indicator),
    \+ piglog_user_thread_unsafe(Indicator),
    (known_thread_safe(Indicator) ; piglog_user_thread_safe(Indicator)).

%% goal_is_deterministic(+Goal)

goal_is_deterministic(Goal) :-
    callable(Goal),
    functor(Goal, Name, Arity),
    Indicator = Name/Arity,
    (known_deterministic(Indicator) ; piglog_user_deterministic(Indicator)).

%% goal_is_safe_for_concurrency(+Goal)
%% A goal is safe for concurrency if it has no side effects and, when a
%% timing module is active, passes recursive clause-body inspection.

goal_is_safe_for_concurrency(Goal) :-
    Goal \== (!),
    \+ goal_has_side_effect(Goal),
    (   catch(nb_getval(piglog2_timing_module, Mod), _, Mod = none),
        Mod \= none,
        callable(Goal),
        functor(Goal, Name, Arity)
    ->  infer_thread_safe_in_module(Name/Arity, Mod, [])
    ;   true   %% No module context - current conservative behaviour (assume safe)
    ).

%% section_safe_for_concurrency(+Section)
%% A section is safe if all its goals are safe and it has no cut boundary.

section_safe_for_concurrency(section(Goals, _, _, meta(_, false))) :-
    maplist(goal_is_safe_for_concurrency, Goals).

%% ─── Recursive thread-safety inference ───────────────────────────────────────

%% infer_thread_safe_in_module(+Indicator, +Module, +Visited)
%%
%% Infer whether the predicate Indicator is thread-safe by inspecting its
%% clauses inside Module.  Visited prevents infinite recursion on mutually
%% recursive predicates (treated conservatively as safe).
%%
%% Priority:
%%   1. Explicitly declared unsafe   → fail
%%   2. Explicitly declared safe     → succeed
%%   3. Already in Visited           → succeed  (recursion guard)
%%   4. Has user-defined clauses in Module → inspect body recursively
%%   5. Otherwise                    → succeed  (assume safe / unknown)

infer_thread_safe_in_module(Indicator, _Module, _Visited) :-
    (known_thread_unsafe(Indicator) ; piglog_user_thread_unsafe(Indicator)),
    !,
    fail.
infer_thread_safe_in_module(Indicator, _Module, _Visited) :-
    (known_thread_safe(Indicator) ; piglog_user_thread_safe(Indicator)),
    !.
infer_thread_safe_in_module(_Indicator, _Module, Visited) :-
    length(Visited, L), L > 20,   %% hard depth limit to prevent runaway
    !.
infer_thread_safe_in_module(Indicator, _Module, Visited) :-
    member(Indicator, Visited),
    !.   %% Recursive call - assume safe to avoid infinite loop
infer_thread_safe_in_module(Indicator, Module, Visited) :-
    Indicator = Name/Arity,
    functor(Head, Name, Arity),
    (   catch(predicate_property(Module:Head, defined), _, fail),
        \+ catch(predicate_property(Module:Head, built_in), _, false),
        \+ catch(predicate_property(Module:Head, imported_from(_)), _, false)
    ->  %% User-defined predicate in Module: inspect all clauses
        forall(
            clause(Module:Head, Body),
            body_thread_safe_in_module(Body, Module, [Indicator|Visited])
        )
    ;   true   %% Unknown, built-in, or imported - assume safe
    ).

%% body_thread_safe_in_module(+Body, +Module, +Visited)

body_thread_safe_in_module(Body, Module, Visited) :-
    flatten_conjunction(Body, Goals),
    forall(
        member(G, Goals),
        goal_part_thread_safe_in_module(G, Module, Visited)
    ).

%% goal_part_thread_safe_in_module(+Goal, +Module, +Visited)

goal_part_thread_safe_in_module(G, Module, Visited) :-
    (callable(G) ->
        functor(G, GN, GA),
        infer_thread_safe_in_module(GN/GA, Module, Visited)
    ;
        true   %% Non-callable (variable etc.) - assume safe
    ).

%% flatten_conjunction(+Body, -Goals)
%% Re-exported here to avoid module-qualifier dependencies in body inspection.

flatten_conjunction((A, B), Goals) :-
    !,
    flatten_conjunction(A, GoalsA),
    flatten_conjunction(B, GoalsB),
    append(GoalsA, GoalsB, Goals).
flatten_conjunction(true, []) :- !.
flatten_conjunction(Goal, [Goal]).

%% classify_if_then_else(+(Cond -> Then ; Else), -Classification)
%% If-then-else branches must not be run concurrently.

classify_if_then_else((Cond -> Then ; Else),
                      ite(Cond, Then, Else, retained_sequential_nondeterministic)).

%% is_disjunction(+Goal)
is_disjunction((_;_)) :- !.
is_disjunction((->(_,_))) :- !.

%% goal_introduces_choicepoints(+Goal)
goal_introduces_choicepoints(Goal) :-
    is_disjunction(Goal), !.
goal_introduces_choicepoints(Goal) :-
    callable(Goal),
    functor(Goal, Name, Arity),
    \+ known_deterministic(Name/Arity),
    \+ piglog_user_deterministic(Name/Arity).
