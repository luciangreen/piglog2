% Piglog 2: Generated SWI-Prolog source.
% This file was produced by the Piglog 2 converter.
% Piglog 2 does not formally verify semantic equivalence.

:- use_module(library(thread)).

:- use_module(library(apply)).

:- use_module(piglog2_runtime).


:- module(concurrent_example,[analyse_document/2,word_score/2,number_score/2]).

analyse_document(A,analysis(B,C)) :-
    concurrent(2,
        [
            word_score(A,B),
            number_score(A,C)
        ],
        []).

word_score(A,B) :-
    length(A,C),
    cpu_work(1500000,D),
    B is C+D.

number_score(A,B) :-
    sum_list(A,C),
    cpu_work(1500000,D),
    B is C+D.

cpu_work(A,B) :-
    cpu_work_(A,0,B).

cpu_work_(0,A,A) :-
    !.

cpu_work_(A,B,C) :-
    A>0,
    D is (B+A)mod 1000003,
    E is A-1,
    cpu_work_(E,D,C).

