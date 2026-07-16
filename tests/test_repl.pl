%% test_repl.pl
%% REPL command tests for Piglog 2.

:- use_module(library(plunit)).
:- use_module('../piglog2').
:- use_module('../piglog2_safety').

:- begin_tests(repl).

%% ─── Output-only command ─────────────────────────────────────────────────────

test(piglog_output_from_terms) :-
    Terms = [(fact(1)), (fact(2))],
    with_output_to(string(Output),
        piglog_output(terms(Terms), [])),
    sub_string(Output, _, _, _, "fact(1)").

test(piglog_output_directive_preserved) :-
    Terms = [(:- module(test, []))],
    with_output_to(string(Output),
        piglog_output(terms(Terms), [])),
    sub_string(Output, _, _, _, "module(test").

%% ─── Convert command ─────────────────────────────────────────────────────────

test(piglog_convert_returns_terms) :-
    Terms = [(foo :- true)],
    piglog_convert(terms(Terms), Generated, _Report),
    Generated \= [].

test(piglog_convert_with_report) :-
    Terms = [(foo :- true)],
    piglog_convert(terms(Terms), _Generated, conversion_report(_)).

%% ─── Write command ───────────────────────────────────────────────────────────

test(piglog_write_to_file) :-
    Terms = [(foo(1)), (foo(2))],
    tmp_file(piglog2_test, TmpFile),
    atom_concat(TmpFile, '.pl', OutFile),
    piglog_write(terms(Terms), OutFile),
    exists_file(OutFile),
    delete_file(OutFile).

%% ─── Report command ──────────────────────────────────────────────────────────

test(piglog_report_runs) :-
    Terms = [(p(X, Y) :- atom(X), number(Y))],
    with_output_to(string(Output),
        piglog_report(terms(Terms))),
    sub_string(Output, _, _, _, "PIGLOG2").

%% ─── File operations ─────────────────────────────────────────────────────────

test(piglog_output_file) :-
    absolute_file_name('../examples/example.pl', ExFile, [file_type(prolog), access(exist)]),
    with_output_to(string(Output),
        piglog_output_file(ExFile)),
    Output \= ''.

%% ─── Alternative interface ───────────────────────────────────────────────────

test(piglog_output_action) :-
    Terms = [(fact(1))],
    with_output_to(string(_),
        piglog(terms(Terms), output)).

test(piglog_convert_action) :-
    Terms = [(fact(1))],
    piglog(terms(Terms), convert(Generated)),
    Generated \= [].

%% ─── Configuration ───────────────────────────────────────────────────────────

test(set_and_get_config) :-
    piglog_set_config(maximum_threads, 8),
    piglog2_config(maximum_threads, 8).

test(reset_config) :-
    piglog_set_config(maximum_threads, 8),
    piglog_reset_config(maximum_threads),
    piglog2_config(maximum_threads, Default),
    Default \= 8.

:- end_tests(repl).
