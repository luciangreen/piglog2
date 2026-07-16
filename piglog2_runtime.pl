%% piglog2_runtime.pl
%% Runtime helpers for Piglog 2 generated code.
%%
%% This module provides helper predicates used by generated Piglog code.
%% It is NOT a Piglog scheduler. Helper predicates perform fixed mechanical
%% work: running goals in threads, collecting results, and cleanup.
%%
%% Generated code must include:
%%   :- use_module(piglog2_runtime).

:- module(piglog2_runtime, [
    piglog2_run_concurrent/2,
    piglog2_run_workers/3,
    piglog2_collect_tagged/3
]).

:- use_module(library(thread)).

%% piglog2_run_concurrent(+Goals, +Options)
%% Run a list of independent goals concurrently using concurrent/3.
%% Goals must not share output variables.

piglog2_run_concurrent(Goals, Options) :-
    length(Goals, N),
    concurrent(N, Goals, Options).

%% piglog2_run_workers(+WorkerCalls, +OutputVars, +Options)
%%
%% Run a list of worker calls concurrently.
%% Each WorkerCall is a goal that produces outputs by sending tagged
%% messages to a queue.
%%
%% WorkerCalls: list of goals to run in parallel
%% OutputVars: list of variables to be bound with results (in order)
%% Options: thread options

piglog2_run_workers(WorkerCalls, OutputVars, Options) :-
    length(WorkerCalls, N),
    setup_call_cleanup(
        message_queue_create(Queue, []),
        piglog2_dispatch_and_collect(WorkerCalls, Queue, N, OutputVars, Options),
        message_queue_destroy(Queue)
    ).

piglog2_dispatch_and_collect([], _Queue, 0, [], _Options) :- !.
piglog2_dispatch_and_collect(WorkerCalls, Queue, N, OutputVars, Options) :-
    piglog2_dispatch_workers(WorkerCalls, Queue, Options, 1, ThreadIds),
    piglog2_collect_tagged(Queue, N, TaggedResults),
    piglog2_join_all(ThreadIds),
    piglog2_bind_results(TaggedResults, 1, OutputVars).

piglog2_dispatch_workers([], _, _, _, []).
piglog2_dispatch_workers([Call|Rest], Queue, Options, Idx, [T|Ts]) :-
    WrappedCall = (Call, thread_send_message(Queue, piglog2_result(Idx, done))),
    thread_create(WrappedCall, T, Options),
    Idx1 is Idx + 1,
    piglog2_dispatch_workers(Rest, Queue, Options, Idx1, Ts).

%% piglog2_collect_tagged(+Queue, +N, -TaggedResults)
%% Collect N tagged messages from Queue.

piglog2_collect_tagged(_, 0, []) :- !.
piglog2_collect_tagged(Queue, N, [Tag-V|Rest]) :-
    N > 0,
    thread_get_message(Queue, piglog2_result(Tag, V)),
    N1 is N - 1,
    piglog2_collect_tagged(Queue, N1, Rest).

piglog2_join_all([]).
piglog2_join_all([T|Ts]) :-
    thread_join(T, Status),
    ( Status = true -> true
    ; Status = exception(E) -> throw(E)
    ; true
    ),
    piglog2_join_all(Ts).

piglog2_bind_results(_, _, []).
piglog2_bind_results(Tagged, Idx, [V|Vs]) :-
    (member(Idx-Result, Tagged) ->
        V = Result
    ;
        true  % variable stays unbound if no result
    ),
    Idx1 is Idx + 1,
    piglog2_bind_results(Tagged, Idx1, Vs).

%% piglog2_run_pair(+Goal1, +Goal2)
%% Run two goals in parallel, collecting bindings via thread_create/join.
%% Variables in Goal1 and Goal2 are shared with the calling environment.
%% NOTE: Thread variable sharing requires both goals to use shared var refs.

piglog2_run_pair(Goal1, Goal2) :-
    thread_create(Goal1, T1, []),
    thread_create(Goal2, T2, []),
    thread_join(T1, Status1),
    thread_join(T2, Status2),
    piglog2_check_status(Status1),
    piglog2_check_status(Status2).

piglog2_check_status(true) :- !.
piglog2_check_status(false) :- !, fail.
piglog2_check_status(exception(E)) :- throw(E).
piglog2_check_status(_) :- true.  % joined with other status

%% piglog2_run_group(+Goals)
%% Run a list of goals in parallel using thread_create/join.
%% Goals must be safe to run in separate threads.

piglog2_run_group(Goals) :-
    maplist(piglog2_create_thread, Goals, Threads),
    maplist(piglog2_join_thread, Threads).

piglog2_create_thread(Goal, Thread) :-
    thread_create(Goal, Thread, []).

piglog2_join_thread(Thread) :-
    thread_join(Thread, Status),
    piglog2_check_status(Status).
