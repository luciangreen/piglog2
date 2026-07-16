%% example2.pl
%% Example with inline Piglog 2 declarations.

:- module(example2, [report/2, prepare/0]).

%% Declare that these predicates are long and thread-safe
:- use_module(piglog2, [piglog_long/1, piglog_thread_safe/1]).
:- piglog_long(analyse_words/2).
:- piglog_long(analyse_numbers/2).
:- piglog_long(rebuild_index/0).
:- piglog_long(regenerate_cache/0).
:- piglog_long(precompute_tables/0).
:- piglog_thread_safe(analyse_words/2).
:- piglog_thread_safe(analyse_numbers/2).
:- piglog_thread_safe(rebuild_index/0).
:- piglog_thread_safe(regenerate_cache/0).
:- piglog_thread_safe(precompute_tables/0).

%% report/2 - two independent long sections
report(Input, Report) :-
    analyse_words(Input, Words),
    analyse_numbers(Input, Numbers),
    combine(Words, Numbers, Report).

%% prepare/0 - three independent goals
prepare :-
    rebuild_index,
    regenerate_cache,
    precompute_tables.

%% Stubs
analyse_words(_, words_result).
analyse_numbers(_, numbers_result).
combine(W, N, combined(W, N)).
rebuild_index.
regenerate_cache.
precompute_tables.
