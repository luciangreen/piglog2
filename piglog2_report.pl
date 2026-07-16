%% piglog2_report.pl
%% Conversion reporting and diagnostics for Piglog 2.
%%
%% Generates human-readable conversion reports explaining:
%%   - which sections were converted to concurrent code
%%   - which sections remained sequential and why
%%   - estimated costs and savings

:- module(piglog2_report, [
    format_report/2,
    format_report/3,
    print_report/1,
    print_report/2,
    report_decision/2,
    decision_label/2
]).

%% decision_label(?Decision, ?Label)

decision_label(converted_concurrent,               'converted to concurrent').
decision_label(converted_concurrent_maplist,        'converted to concurrent_maplist').
decision_label(retained_sequential_all,             'retained sequential (all sections)').
decision_label(retained_sequential_short,           'retained sequential (too short)').
decision_label(retained_sequential_dependent,       'retained sequential (data dependency)').
decision_label(retained_sequential_effectful,       'retained sequential (side effects)').
decision_label(retained_sequential_nondeterministic,'retained sequential (nondeterministic)').
decision_label(retained_sequential_thread_unsafe,   'retained sequential (thread-unsafe)').
decision_label(retained_sequential_unknown,         'retained sequential (unknown safety)').
decision_label(retained_sequential_unsupported,     'retained sequential (unsupported)').

%% print_report(+Report)

print_report(Report) :-
    print_report(Report, []).

print_report(Reports, Options) :-
    is_list(Reports),
    !,
    maplist(print_single_report(Options), Reports).
print_report(Report, Options) :-
    print_single_report(Options, Report).

print_single_report(_Options, report_directive(D)) :-
    format("PIGLOG2 INFO: directive ~w (preserved)~n", [D]).
print_single_report(_Options, report_fact(F)) :-
    functor(F, Name, Arity),
    format("PIGLOG2 INFO: fact ~w/~w (preserved)~n", [Name, Arity]).
print_single_report(_Options, report(Indicator, retained_sequential_all, _)) :-
    format("PIGLOG2 INFO:~n"),
    format("  predicate: ~w~n", [Indicator]),
    format("  action: retained sequential~n"),
    format("  reason: no independent sections found~n~n").
print_single_report(_Options, report(Indicator, converted, GroupReports)) :-
    format("PIGLOG2 INFO:~n"),
    format("  predicate: ~w~n", [Indicator]),
    format("  action: converted~n"),
    maplist(print_group_report([]), GroupReports),
    nl.
print_single_report(_Options, Report) :-
    format("PIGLOG2 INFO: ~w~n", [Report]).

print_group_report(_Options, group_report(
        predicate(_Pred),
        sections(Set),
        estimated_sequential(SeqMs),
        estimated_concurrent(ConcMs),
        estimated_saving(Saving),
        construct(Construct),
        decision(Decision))) :-
    !,
    decision_label(Decision, Label),
    format("  group sections: ~w~n", [Set]),
    format("  estimated sequential: ~2f ms~n", [SeqMs]),
    format("  estimated concurrent: ~2f ms~n", [ConcMs]),
    format("  estimated saving: ~2f ms~n", [Saving]),
    format("  construct: ~w~n", [Construct]),
    format("  decision: ~w~n", [Label]).
print_group_report(_Options, R) :-
    format("  group: ~w~n", [R]).

%% format_report(+Report, -String)

format_report(Report, String) :-
    format_report(Report, [], String).

format_report(Report, Options, String) :-
    with_output_to(string(String), print_report(Report, Options)).

%% report_decision(?Report, ?Decision)

report_decision(report(_, Decision, _), Decision).
report_decision(report(_, Decision), Decision).
