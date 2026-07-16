%% piglog2_reader.pl
%% Source reading for Piglog 2.
%%
%% Reads Prolog source from files, term lists, modules, or predicates.

:- module(piglog2_reader, [
    read_source/2
]).

:- use_module(library(readutil)).

%% read_source(+Source, -Terms)
%%
%% Source is one of:
%%   file(Path)                  - read from a file
%%   terms(TermList)             - already-parsed terms
%%   module(Module)              - extract from a loaded module
%%   predicate(Module:Name/Arity) - extract specific predicate

read_source(file(Path), Terms) :-
    !,
    read_source_file(Path, Terms).
read_source(terms(Terms), Terms) :-
    !,
    (is_list(Terms) -> true ;
     throw(piglog2_error(invalid_source, terms_not_a_list))).
read_source(module(Module), Terms) :-
    !,
    read_source_module(Module, Terms).
read_source(predicate(Module:Name/Arity), Terms) :-
    !,
    read_source_predicate(Module, Name, Arity, Terms).
read_source(Source, _) :-
    throw(piglog2_error(invalid_source, Source)).

%% read_source_file(+Path, -Terms)

read_source_file(Path, Terms) :-
    (exists_file(Path) ->
        true
    ;
        throw(piglog2_error(file_not_found, Path))
    ),
    setup_call_cleanup(
        open(Path, read, Stream, []),
        read_stream_terms(Stream, Terms),
        close(Stream)
    ).

read_stream_terms(Stream, Terms) :-
    read_term(Stream, T, [variable_names(_), module(user)]),
    (T == end_of_file ->
        Terms = []
    ;
        Terms = [T|Rest],
        read_stream_terms(Stream, Rest)
    ).

%% read_source_module(+Module, -Terms)
%% Read clauses from a loaded module.

read_source_module(Module, Terms) :-
    (current_module(Module) ->
        true
    ;
        throw(piglog2_error(module_not_loaded, Module))
    ),
    findall(Clause, module_clause(Module, Clause), Terms).

module_clause(Module, (Head :- Body)) :-
    predicate_property(Module:Head, defined),
    \+ predicate_property(Module:Head, imported_from(_)),
    \+ predicate_property(Module:Head, built_in),
    clause(Module:Head, Body).
module_clause(Module, Head) :-
    predicate_property(Module:Head, defined),
    \+ predicate_property(Module:Head, imported_from(_)),
    \+ predicate_property(Module:Head, built_in),
    clause(Module:Head, true),
    functor(Head, _, _).

%% read_source_predicate(+Module, +Name, +Arity, -Terms)

read_source_predicate(Module, Name, Arity, Terms) :-
    functor(Head, Name, Arity),
    (predicate_property(Module:Head, defined) ->
        true
    ;
        throw(piglog2_error(predicate_not_defined, Module:Name/Arity))
    ),
    findall(Clause, predicate_clause(Module, Head, Clause), Terms).

predicate_clause(Module, Head, (Head :- Body)) :-
    clause(Module:Head, Body),
    Body \== true.
predicate_clause(Module, Head, Head) :-
    clause(Module:Head, true).

%% read_source_string(+String, -Terms)
%% Helper: read terms from a string.

read_source_string(String, Terms) :-
    term_to_atom(_, String),  % validate it's a string
    atom_to_term(String, Term, _),
    (Term == end_of_file ->
        Terms = []
    ;
        Terms = [Term]
    ).

%% read_source_atom(+Atom, -Terms)
%% Read multiple terms from an atom (atom must be valid Prolog text).

read_source_atom(Atom, Terms) :-
    atom_to_term(Atom, _, _),
    term_to_atom(_, Atom),  % verify
    setup_call_cleanup(
        open_codes_stream(Codes, Stream),
        (atom_codes(Atom, Codes), read_stream_terms(Stream, Terms)),
        close(Stream)
    ).
