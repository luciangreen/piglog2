%% piglog2_calibrate.pl
%% Calibration for Piglog 2.
%%
%% Measures local costs for concurrency operations:
%%   - thread creation
%%   - thread joining
%%   - message queue create/destroy
%%   - sending/receiving a message
%%   - trivial concurrent/3 invocation
%%
%% Results are stored in piglog2_calibration/2 and can be used
%% to refine the concurrency overhead estimate.

:- module(piglog2_calibrate, [
    piglog_calibrate/0,
    piglog_calibrate/1,
    calibration_summary/0
]).

:- use_module(piglog2_estimator).

%% piglog_calibrate/0
%% Run all calibration measurements with default repetitions.

piglog_calibrate :-
    piglog_calibrate([repetitions(20)]).

%% piglog_calibrate(+Options)

piglog_calibrate(Options) :-
    option_reps(Options, Reps),
    format("Piglog 2: calibrating concurrency overhead...~n"),
    calibrate_thread_create(Reps, CreateMs),
    calibrate_thread_join(Reps, JoinMs),
    calibrate_queue(Reps, QueueMs),
    calibrate_concurrent3(Reps, ConcMs),
    store_calibration(thread_create, CreateMs),
    store_calibration(thread_join, JoinMs),
    store_calibration(queue_roundtrip, QueueMs),
    store_calibration(concurrent3_trivial, ConcMs),
    % Combined overhead estimate
    OverheadMs is CreateMs + JoinMs,
    store_calibration(thread_overhead, OverheadMs),
    format("Calibration complete:~n"),
    format("  thread_create:     ~4f ms~n", [CreateMs]),
    format("  thread_join:       ~4f ms~n", [JoinMs]),
    format("  queue_roundtrip:   ~4f ms~n", [QueueMs]),
    format("  concurrent3_trivial: ~4f ms~n", [ConcMs]),
    format("  estimated overhead:  ~4f ms~n", [OverheadMs]).

option_reps(Options, Reps) :-
    (member(repetitions(Reps), Options) -> true ; Reps = 20).

calibrate_thread_create(Reps, Ms) :-
    measure_operation(Reps,
        (thread_create(true, T, []),
         thread_join(T, _)),
        TotalMs),
    Ms is TotalMs / 2.0.

calibrate_thread_join(Reps, Ms) :-
    % Approximate: same as create/join but we attribute half to join
    calibrate_thread_create(Reps, CreateJoinMs),
    Ms is CreateJoinMs.

calibrate_queue(Reps, Ms) :-
    measure_operation(Reps,
        (message_queue_create(Q),
         thread_send_message(Q, test_msg),
         thread_get_message(Q, _),
         message_queue_destroy(Q)),
        Ms).

calibrate_concurrent3(Reps, Ms) :-
    measure_operation(Reps,
        concurrent(1, [true], []),
        Ms).

measure_operation(Reps, Goal, AvgMs) :-
    numlist(1, Reps, _),
    findall(T, (
        between(1, Reps, _),
        statistics(walltime, [Start|_]),
        (call(Goal) -> true ; true),
        statistics(walltime, [End|_]),
        T is End - Start
    ), Times),
    (Times = [] ->
        AvgMs = 1.0
    ;
        msort(Times, Sorted),
        length(Sorted, Len),
        Mid is Len // 2,
        nth0(Mid, Sorted, AvgMs)
    ).

%% calibration_summary/0
%% Print current calibration data.

calibration_summary :-
    format("Piglog 2 calibration data:~n"),
    (piglog2_calibration(_, _) ->
        forall(piglog2_calibration(K, V),
               format("  ~w: ~4f ms~n", [K, V]))
    ;
        format("  (no calibration data; run piglog_calibrate/0)~n")
    ).
