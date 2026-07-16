%% piglog2_printer.pl
%% Generated-code printing for Piglog 2.
%%
%% Prints generated Prolog terms in a readable, valid SWI-Prolog format.

:- module(piglog2_printer, [
    print_piglog_terms/1,
    print_piglog_terms/2,
    print_piglog_term/1,
    print_piglog_term/2,
    terms_to_string/2,
    required_imports/1
]).

%% required_imports(-Imports)
%% Returns required library imports for generated code.

required_imports([
    (:- use_module(library(thread))),
    (:- use_module(library(apply))),
    (:- use_module(piglog2_runtime))
]).

%% print_piglog_terms(+Terms)
%% Print all terms to current output.

print_piglog_terms(Terms) :-
    print_piglog_terms(Terms, []).

print_piglog_terms(Terms, Options) :-
    required_imports(Imports),
    (option_source_comments(Options) ->
        format("% Piglog 2: Generated SWI-Prolog source.~n"),
        format("% This file was produced by the Piglog 2 converter.~n"),
        format("% Piglog 2 does not formally verify semantic equivalence.~n~n")
    ;
        true
    ),
    print_terms_list(Imports),
    nl,
    print_terms_list(Terms).

print_terms_list([]).
print_terms_list([Term|Rest]) :-
    print_piglog_term(Term),
    nl,
    print_terms_list(Rest).

%% print_piglog_term(+Term)
%% Print a single term.

print_piglog_term(Term) :-
    print_piglog_term(Term, []).

print_piglog_term((:- Directive), _Options) :-
    !,
    format(":- ~w.~n", [Directive]).
print_piglog_term((Head :- Body), Options) :-
    !,
    (option_source_comments(Options) -> true ; true),
    format("~w :-~n", [Head]),
    print_body(Body, 4),
    format(".~n").
print_piglog_term(Fact, _Options) :-
    callable(Fact),
    !,
    format("~w.~n", [Fact]).
print_piglog_term(Term, _Options) :-
    format("~w.~n", [Term]).

option_source_comments(Options) :-
    (member(comments(true), Options) -> true ;
     \+ member(comments(false), Options)).

%% print_body(+Body, +Indent)
%% Pretty-print a clause body with indentation.

print_body(Body, Indent) :-
    print_body_term(Body, Indent).

print_body_term((A, B), Indent) :-
    !,
    print_body_term(A, Indent),
    format(",~n"),
    print_body_term(B, Indent).
print_body_term((Cond -> Then ; Else), Indent) :-
    !,
    print_indent(Indent),
    format("(   "),
    print_inline(Cond),
    format("~n"),
    print_indent(Indent),
    format("->  "),
    print_inline(Then),
    format("~n"),
    print_indent(Indent),
    format(";   "),
    print_inline(Else),
    format("~n"),
    print_indent(Indent),
    format(")").
print_body_term((Cond -> Then), Indent) :-
    !,
    print_indent(Indent),
    format("(   "),
    print_inline(Cond),
    format("~n"),
    print_indent(Indent),
    format("->  "),
    print_inline(Then),
    format("~n"),
    print_indent(Indent),
    format(")").
print_body_term(concurrent(N, Goals, Opts), Indent) :-
    !,
    print_indent(Indent),
    format("concurrent(~w,~n", [N]),
    Indent2 is Indent + 4,
    print_indent(Indent2),
    format("[~n"),
    Indent3 is Indent2 + 4,
    print_goal_list(Goals, Indent3),
    print_indent(Indent2),
    format("],~n"),
    print_indent(Indent2),
    format("~w)", [Opts]).
print_body_term(Goal, Indent) :-
    print_indent(Indent),
    format("~w", [Goal]).

print_inline(Term) :-
    format("~w", [Term]).

print_goal_list([], _).
print_goal_list([G], Indent) :-
    !,
    print_indent(Indent),
    format("~w~n", [G]).
print_goal_list([G|Rest], Indent) :-
    print_indent(Indent),
    format("~w,~n", [G]),
    print_goal_list(Rest, Indent).

print_indent(0) :- !.
print_indent(N) :-
    N > 0,
    put_char(' '),
    N1 is N - 1,
    print_indent(N1).

%% terms_to_string(+Terms, -String)
%% Convert a list of terms to a string representation.

terms_to_string(Terms, String) :-
    with_output_to(string(String), print_piglog_terms(Terms)).

%% term_to_piglog_string(+Term, -String)

term_to_piglog_string(Term, String) :-
    with_output_to(string(String), print_piglog_term(Term)).
