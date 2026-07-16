%% piglog2_loader.pl
%% Generated-code loading for Piglog 2.
%%
%% Loads generated Prolog terms into a separate module.
%% The generated module is isolated from the user module.

:- module(piglog2_loader, [
    load_generated_terms/3,
    load_generated_terms/4,
    unload_generated_module/1,
    make_module_name/3,
    loaded_module/2
]).

:- use_module(piglog2_config).

%% Track loaded modules (dynamic)
:- dynamic loaded_module/2.
% loaded_module(ModuleName, TempFile)

%% make_module_name(+Source, +Options, -ModuleName)

make_module_name(file(Path), _Options, ModuleName) :-
    !,
    file_base_name(Path, Base),
    file_name_extension(Stem, _, Base),
    sanitise_atom(Stem, Clean),
    piglog2_config(generated_module_prefix, Prefix),
    atomic_list_concat([Prefix, '_', Clean], ModuleName).
make_module_name(_, Options, ModuleName) :-
    (member(module_name(ModuleName), Options) ->
        true
    ;
        gensym(piglog2_generated_, ModuleName)
    ).

sanitise_atom(Atom, Clean) :-
    atom_chars(Atom, Chars),
    maplist(sanitise_char, Chars, CleanChars),
    atom_chars(Clean, CleanChars).

sanitise_char(C, '_') :-
    \+ char_type(C, alnum),
    !.
sanitise_char(C, C).

%% load_generated_terms(+Terms, +ModuleName, -LoadedModule)

load_generated_terms(Terms, ModuleName, LoadedModule) :-
    load_generated_terms(Terms, ModuleName, [], LoadedModule).

load_generated_terms(Terms, ModuleName, Options, LoadedModule) :-
    % If module already loaded and reload not requested, check option
    (loaded_module(ModuleName, OldFile) ->
        (member(reload(true), Options) ->
            catch(unload_module(ModuleName), _, true),
            delete_file(OldFile),
            retract(loaded_module(ModuleName, OldFile))
        ;
            throw(piglog2_error(module_already_loaded, ModuleName))
        )
    ;
        true
    ),
    % Write terms to a temporary file
    tmp_file_name(ModuleName, TmpFile),
    write_terms_to_file(Terms, ModuleName, TmpFile),
    % Load the file
    (catch(
        load_files(TmpFile, [module(ModuleName), silent(true)]),
        Error,
        (delete_file(TmpFile),
         throw(piglog2_error(load_failure, ModuleName, Error)))
    ) ->
        assertz(loaded_module(ModuleName, TmpFile)),
        LoadedModule = ModuleName
    ;
        delete_file(TmpFile),
        throw(piglog2_error(load_failure, ModuleName, unknown))
    ).

tmp_file_name(ModuleName, TmpFile) :-
    tmp_file(piglog2_gen, Base),
    atomic_list_concat([Base, '_', ModuleName, '.pl'], TmpFile).

write_terms_to_file(Terms, ModuleName, File) :-
    setup_call_cleanup(
        open(File, write, Stream),
        (
            format(Stream, ":- module(~w, []).~n~n", [ModuleName]),
            format(Stream, ":- use_module(library(thread)).~n", []),
            format(Stream, ":- use_module(library(apply)).~n~n", []),
            maplist(write_term_to_stream(Stream), Terms)
        ),
        close(Stream)
    ).

write_term_to_stream(Stream, Term) :-
    write_canonical(Stream, Term),
    format(Stream, ".~n", []).

%% unload_generated_module(+ModuleName)

unload_generated_module(ModuleName) :-
    (loaded_module(ModuleName, TmpFile) ->
        catch(unload_module(ModuleName), _, true),
        (exists_file(TmpFile) -> delete_file(TmpFile) ; true),
        retract(loaded_module(ModuleName, TmpFile))
    ;
        true  % not loaded, silently succeed
    ).

%% run_goal_in_module(+ModuleName, +Goal)

run_goal_in_module(ModuleName, Goal) :-
    (loaded_module(ModuleName, _) ->
        catch(
            call(ModuleName:Goal),
            Error,
            throw(piglog2_error(execution_failure, ModuleName, Goal, Error))
        )
    ;
        throw(piglog2_error(module_not_loaded, ModuleName))
    ).
