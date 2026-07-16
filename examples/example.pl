%% example.pl
%% Example source file for Piglog 2 conversion.

:- module(example, [report/2, prepare/0, normalise/3]).

%% Declare costs so the estimator knows these are expensive
:- use_module(library(lists)).

%% report/2 - two independent long sections
%% analyse_words and analyse_numbers are independent and both consume Input
report(Input, Report) :-
    analyse_words(Input, Words),
    analyse_numbers(Input, Numbers),
    combine(Words, Numbers, Report).

%% prepare/0 - three independent goals with no result sharing
prepare :-
    rebuild_index,
    regenerate_cache,
    precompute_tables.

%% normalise/3 - sequential (b depends on a's output)
normalise(Input, Mode, Output) :-
    load(Input, Data),
    normalise_data(Data, Mode, Normalised),
    inspect(Normalised, Output).

%% Helper stubs (sequential)
analyse_words(_, words_result).
analyse_numbers(_, numbers_result).
combine(W, N, combined(W, N)).
rebuild_index.
regenerate_cache.
precompute_tables.
load(_, data).
normalise_data(Data, _, Data).
inspect(D, D).
