:- module(concurrent_example, [
    analyse_document/2,
    word_score/2,
    number_score/2
]).

% The two analyses depend only on Document.
% Neither analysis requires the other one's result.
analyse_document(Document, analysis(Words, Numbers)) :-
    word_score(Document, Words),
    number_score(Document, Numbers).

% Artificially long deterministic computations.
word_score(Document, Score) :-
    length(Document, Length),
    cpu_work(1500000, WordWork),
    Score is Length + WordWork.

number_score(Document, Score) :-
    sum_list(Document, Sum),
    cpu_work(1500000, NumberWork),
    Score is Sum + NumberWork.

cpu_work(Iterations, Result) :-
    cpu_work_(Iterations, 0, Result).

cpu_work_(0, Accumulator, Accumulator) :-
    !.
cpu_work_(Iterations, Accumulator, Result) :-
    Iterations > 0,
    NextAccumulator is (Accumulator + Iterations) mod 1000003,
    NextIterations is Iterations - 1,
    cpu_work_(NextIterations, NextAccumulator, Result).