%% piglog2_config.pl
%% Configuration management for Piglog 2.
%%
%% Piglog 2: Automatic Concurrent-Prolog Converter and REPL Runner.

:- module(piglog2_config, [
    piglog2_config/2,
    piglog2_set_config/2,
    piglog2_reset_config/1,
    piglog2_reset_all_config/0,
    piglog2_default_config/2
]).

%% piglog2_default_config(?Key, ?Value)
%% Default configuration values.

piglog2_default_config(minimum_concurrent_time,   milliseconds(10)).
piglog2_default_config(minimum_expected_saving,   milliseconds(2)).
piglog2_default_config(maximum_threads,           4).
piglog2_default_config(estimation_method,         measured).
piglog2_default_config(benchmark_repetitions,     5).
piglog2_default_config(generated_module_prefix,   piglog2_generated).
piglog2_default_config(report_detail,             summary).
piglog2_default_config(source_comments,           true).
piglog2_default_config(concurrency_overhead_ms,   1.0).

:- dynamic piglog2_user_config/2.

%% piglog2_config(?Key, ?Value)
%% Retrieve a configuration value (user override or default).

piglog2_config(Key, Value) :-
    piglog2_user_config(Key, Value),
    !.
piglog2_config(Key, Value) :-
    piglog2_default_config(Key, Value).

%% piglog2_set_config(+Key, +Value)
%% Set a user configuration value.

piglog2_set_config(Key, Value) :-
    retractall(piglog2_user_config(Key, _)),
    assertz(piglog2_user_config(Key, Value)).

%% piglog2_reset_config(+Key)
%% Reset a key to its default.

piglog2_reset_config(Key) :-
    retractall(piglog2_user_config(Key, _)).

%% piglog2_reset_all_config/0
%% Reset all user configuration to defaults.

piglog2_reset_all_config :-
    retractall(piglog2_user_config(_, _)).

%% Internal helpers

milliseconds_value(milliseconds(Ms), Ms) :- !.
milliseconds_value(Ms, Ms) :- number(Ms).
