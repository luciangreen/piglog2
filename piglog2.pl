%% piglog2.pl
%% Piglog 2: Automatic Concurrent-Prolog Converter and REPL Runner.
%%
%% Piglog 2 replaces Piglog. It is an in-SWI-Prolog source converter and runner
%% that estimates the runtime of independent program sections during conversion
%% and inserts direct concurrent constructs where sections are long enough and
%% concurrency is appropriate. It can output, run, or output and run generated
%% Piglog code. Generated code contains fixed concurrency decisions rather than
%% Piglog runtime scheduling or profitability heuristics. Piglog 2 does not
%% formally verify semantic equivalence.
%%
%% Usage:
%%   ?- use_module(piglog2).
%%   ?- piglog_output(file('example.pl')).
%%   ?- piglog_run(file('example.pl'), main).
%%   ?- piglog_output_run(file('example.pl'), main).

:- module(piglog2, [
    %% Primary API
    piglog_output/1,
    piglog_output/2,
    piglog_run/2,
    piglog_run/3,
    piglog_output_run/2,
    piglog_output_run/3,
    piglog_convert/2,
    piglog_convert/3,
    piglog_write/2,
    piglog_write/3,
    piglog_report/1,
    piglog_report/2,
    %% REPL interface
    piglog_begin/0,
    %% File interface
    piglog_output_file/1,
    piglog_output_file/2,
    piglog_run_file/2,
    piglog_output_run_file/3,
    %% Configuration
    piglog_set_config/2,
    piglog_reset_config/1,
    %% Calibration
    piglog_calibrate/0,
    %% User declarations (also available from piglog2_safety)
    piglog_minimum_concurrent_time/1,
    piglog_max_threads/1,
    %% Alternative interface
    piglog/2,
    piglog/3
]).

:- use_module(piglog2_config).
:- use_module(piglog2_reader).
:- use_module(piglog2_analyser).
:- use_module(piglog2_safety).
:- use_module(piglog2_estimator).
:- use_module(piglog2_transformer).
:- use_module(piglog2_printer).
:- use_module(piglog2_loader).
:- use_module(piglog2_report).
:- use_module(piglog2_calibrate).

:- use_module(library(thread)).
:- use_module(library(apply)).

%% ─── Interactive term buffer ──────────────────────────────────────────────────

:- dynamic piglog_term_buffer/1.

%% ─── Primary conversion pipeline ─────────────────────────────────────────────

%% do_convert(+Source, +Options, -Generated, -Helpers, -Reports)

do_convert(Source, Options, Generated, Helpers, Reports) :-
    read_source(Source, Terms),
    (   should_auto_time(Options)
    ->  format("Piglog 2: timing predicates for concurrent transformation~n"),
        format("  (this may take a notification and several minutes)...~n"),
        preload_terms_for_timing(Terms, Options, TempModule),
        nb_setval(piglog2_timing_module, TempModule),
        AllOptions = [timing_module(TempModule)|Options]
    ;   nb_setval(piglog2_timing_module, none),
        TempModule = none,
        AllOptions = Options
    ),
    transform_terms(Terms, AllOptions,
                    transform_result(GenTerms, Helpers, Reports)),
    nb_setval(piglog2_timing_module, none),
    (   TempModule \= none
    ->  catch(unload_generated_module(TempModule), _, true)
    ;   true
    ),
    (Helpers = [] ->
        Generated = GenTerms
    ;
        append(GenTerms, Helpers, Generated)
    ).

%% should_auto_time(+Options)
%% True when automatic timing (pre-loading + measured benchmarking) is enabled.

should_auto_time(Options) :-
    \+ member(auto_time(false), Options),
    \+ member(estimation_method(static), Options),
    piglog2_config(estimation_method, measured).

%% ─── piglog_output/1,2 ───────────────────────────────────────────────────────

%% piglog_output(+Source)
%% Convert and print generated Piglog code.

piglog_output(Source) :-
    piglog_output(Source, []).

piglog_output(Source, Options) :-
    do_convert(Source, Options, Generated, _Helpers, Reports),
    (member(report(true), Options) ->
        print_report(Reports)
    ;
        true
    ),
    print_piglog_terms(Generated, Options).

%% ─── piglog_run/2,3 ──────────────────────────────────────────────────────────

%% piglog_run(+Source, +Goal)
%% Convert and run the generated code.

piglog_run(Source, Goal) :-
    piglog_run(Source, Goal, []).

piglog_run(Source, Goal, Options) :-
    do_convert(Source, Options, Generated, _Helpers, Reports),
    (member(report(true), Options) ->
        print_report(Reports)
    ;
        true
    ),
    make_module_name(Source, Options, ModuleName),
    load_generated_terms(Generated, ModuleName, Options, LoadedModule),
    (member(trace(true), Options) ->
        trace,
        call(LoadedModule:Goal),
        nodebug
    ;
        call(LoadedModule:Goal)
    ).

%% ─── piglog_output_run/2,3 ───────────────────────────────────────────────────

%% piglog_output_run(+Source, +Goal)
%% Convert, print, and run the generated code.

piglog_output_run(Source, Goal) :-
    piglog_output_run(Source, Goal, []).

piglog_output_run(Source, Goal, Options) :-
    do_convert(Source, Options, Generated, _Helpers, Reports),
    (member(report(true), Options) -> print_report(Reports) ; true),
    nl,
    format("% --- Generated Piglog code ---~n"),
    print_piglog_terms(Generated, Options),
    format("% --- End of generated code ---~n~n"),
    make_module_name(Source, Options, ModuleName),
    load_generated_terms(Generated, ModuleName, Options, LoadedModule),
    format("% Executing ~w in module ~w...~n", [Goal, LoadedModule]),
    call(LoadedModule:Goal),
    format("% Execution complete.~n").

%% ─── piglog_convert/2,3 ──────────────────────────────────────────────────────

%% piglog_convert(+Source, -GeneratedTerms)
%% Convert and return generated terms (without printing or running).

piglog_convert(Source, GeneratedTerms) :-
    piglog_convert(Source, GeneratedTerms, _Report).

piglog_convert(Source, GeneratedTerms, Report) :-
    piglog_convert(Source, GeneratedTerms, Report, []).

piglog_convert(Source, GeneratedTerms, Report, Options) :-
    do_convert(Source, Options, GeneratedTerms, _Helpers, Reports),
    Report = conversion_report(Reports).

%% ─── piglog_write/2,3 ────────────────────────────────────────────────────────

%% piglog_write(+Source, +OutputFile)
%% Convert and write to a file.

piglog_write(Source, OutputFile) :-
    piglog_write(Source, OutputFile, []).

piglog_write(Source, OutputFile, Options) :-
    do_convert(Source, Options, Generated, _Helpers, _Reports),
    (is_list(Generated) -> true ;
     throw(piglog2_error(invalid_generated_terms, OutputFile))),
    setup_call_cleanup(
        open(OutputFile, write, Stream),
        (
            format(Stream, "% Piglog 2: Generated SWI-Prolog source.~n", []),
            format(Stream, "% Generated by piglog_write/2.~n~n", []),
            maplist(write_clause_to_stream(Stream), Generated)
        ),
        close(Stream)
    ),
    format("Piglog 2: written to ~w~n", [OutputFile]).

write_clause_to_stream(Stream, Term) :-
    copy_term(Term, Copy),
    numbervars(Copy, 0, _),
    write_term(Stream, Copy, [quoted(true), numbervars(true)]),
    write(Stream, '.'),
    nl(Stream).

%% ─── piglog_report/1,2 ───────────────────────────────────────────────────────

%% piglog_report(+Source)
%% Print a detailed conversion report.

piglog_report(Source) :-
    piglog_report(Source, []).

piglog_report(Source, Options) :-
    DefaultOpts = [report(true),
                   show_candidates(true),
                   show_dependencies(true),
                   show_estimates(true),
                   show_rejections(true)],
    append(Options, DefaultOpts, AllOpts),
    do_convert(Source, AllOpts, _Generated, _Helpers, Reports),
    format("~n=== Piglog 2 Conversion Report ===~n~n"),
    print_report(Reports, AllOpts),
    format("=== End of Report ===~n~n").

%% ─── REPL interactive interface ──────────────────────────────────────────────

%% piglog_begin/0
%% Start interactive term capture.

piglog_begin :-
    retractall(piglog_term_buffer(_)),
    format("Piglog 2: enter clauses, end with 'end_of_file.'~n"),
    piglog_read_loop([]).

piglog_read_loop(Acc) :-
    read_term(Term, [variable_names(_)]),
    (Term == end_of_file ->
        reverse(Acc, Terms),
        assertz(piglog_term_buffer(Terms)),
        format("Piglog 2: ~w term(s) captured.~n", []),
        length(Terms, N),
        format("Piglog 2: ~w term(s) captured.~n", [N])
    ;
        piglog_read_loop([Term|Acc])
    ).

%% ─── File conversion interface ───────────────────────────────────────────────

piglog_output_file(InputFile) :-
    piglog_output(file(InputFile)).

piglog_output_file(InputFile, OutputFile) :-
    piglog_write(file(InputFile), OutputFile).

piglog_run_file(InputFile, Goal) :-
    piglog_run(file(InputFile), Goal).

piglog_output_run_file(InputFile, OutputFile, Goal) :-
    piglog_write(file(InputFile), OutputFile),
    piglog_run(file(OutputFile), Goal).

%% ─── Configuration interface ─────────────────────────────────────────────────

piglog_set_config(Key, Value) :-
    piglog2_set_config(Key, Value).

piglog_reset_config(Key) :-
    piglog2_reset_config(Key).

%% ─── Declaration directives ──────────────────────────────────────────────────
%% These wrappers call through to piglog2_safety's declaration predicates.
%% They allow source files to contain directives like:
%%   :- piglog_cost(expensive/1, milliseconds(50)).

piglog_minimum_concurrent_time(T) :-
    piglog2_set_config(minimum_concurrent_time, T).

piglog_max_threads(N) :-
    piglog2_set_config(maximum_threads, N).

%% ─── Alternative interface (piglog/2,3) ──────────────────────────────────────

piglog(Source, output) :-
    !, piglog_output(Source).
piglog(Source, run(Goal)) :-
    !, piglog_run(Source, Goal).
piglog(Source, output_and_run(Goal)) :-
    !, piglog_output_run(Source, Goal).
piglog(Source, report) :-
    !, piglog_report(Source).
piglog(Source, convert(Terms)) :-
    !, piglog_convert(Source, Terms).

piglog(Source, Action, _Options) :-
    piglog(Source, Action).

%% ─── Module initialisation ───────────────────────────────────────────────────

:- format("Piglog 2 loaded. Type '?- piglog_output(file(Path)).' to convert a file.~n").
