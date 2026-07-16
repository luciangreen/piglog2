%% run_tests.pl
%% Piglog 2 test runner.
%% Usage: swipl -t halt -g run_all_tests run_tests.pl

:- use_module(library(plunit)).
:- use_module('../piglog2').
:- use_module('../piglog2_safety').
:- use_module('../piglog2_analyser').
:- use_module('../piglog2_estimator').
:- use_module('../piglog2_transformer').
:- use_module('../piglog2_config').

:- load_test_files([]).

run_all_tests :-
    run_tests,
    halt(0).

:- consult(test_basic).
:- consult(test_analysis).
:- consult(test_safety).
:- consult(test_estimation).
:- consult(test_transform).
:- consult(test_repl).
:- consult(test_generated).
