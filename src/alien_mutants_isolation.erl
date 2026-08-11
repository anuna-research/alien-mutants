-module(alien_mutants_isolation).

%% Compiles and loads a single mutant under a module name and code path
%% unique to that mutant, so no two mutants (and no mutant run) can
%% collide with each other or with the real compiled `alien_mutants` app.
%%
%% Placeholder mutant shape (alien_mutants_operators has not landed in
%% this worktree yet): a #mutant{} record holding the original module
%% name, the mutated module AST (the same shape alien_mutants_reader
%% returns: a list of top-level LFE forms, one of which is the
%% `defmodule` form), and the original (unmutated) source form, kept
%% for later reporting per REQ-005. Once alien_mutants_operators lands
%% it should either produce this same shape or this module should be
%% adjusted to accept whatever it produces.

-export([new/3, load/1, unload/1]).
-export_type([mutant/0]).

-record(mutant, {
    module :: atom(),
    ast :: [term()],
    source :: term()
}).

-type mutant() :: #mutant{}.

-define(SCRATCH_ROOT, "_build/mutants").

%% new(Module, Ast, Source) -> Mutant.
%%  Constructs a mutant: Module is the original module name, Ast is
%%  the mutated module AST (list of top-level LFE forms, one of which
%%  is `defmodule`), Source is the original unmutated form.
-spec new(atom(), [term()], term()) -> mutant().
new(Module, Ast, Source) ->
    #mutant{module = Module, ast = Ast, source = Source}.

%% load(Mutant) -> {ok, LoadedModule} | {error, Reason}.
%%  Compiles Mutant's AST under a fresh, unique module name and loads
%%  it from a scratch directory dedicated to that module name. The
%%  caller can then call LoadedModule:Fun(...) directly and must call
%%  unload/1 when done.
-spec load(mutant()) -> {ok, atom()} | {error, term()}.
load(#mutant{module = Module, ast = Forms}) ->
    Unique = unique_module_name(Module),
    RenamedForms = rename_module(Forms, Unique),
    case lfe_comp:forms(RenamedForms, [binary, return]) of
        {ok, [{ok, Unique, Binary, _ModWarnings}], _TopWarnings} ->
            load_binary(Unique, Binary);
        {ok, [{ok, Other, _Binary, _ModWarnings}], _TopWarnings} ->
            {error, {module_name_mismatch, Unique, Other}};
        {error, Errors, Warnings} ->
            {error, {compile_error, Errors, Warnings}}
    end.

%% unload(LoadedModule) -> ok.
%%  Purges and deletes the loaded module's code and removes its
%%  scratch directory, leaving no residue for the next mutant.
-spec unload(atom()) -> ok.
unload(LoadedModule) ->
    code:purge(LoadedModule),
    code:delete(LoadedModule),
    _ = file:del_dir_r(scratch_dir(LoadedModule)),
    ok.

%% -- internal ---------------------------------------------------------

unique_module_name(Module) ->
    Id = erlang:unique_integer([positive, monotonic]),
    list_to_atom(atom_to_list(Module) ++ "_mutant_" ++ integer_to_list(Id)).

rename_module([[defmodule, _OldName | Rest] | OtherForms], NewName) ->
    [[defmodule, NewName | Rest] | OtherForms].

load_binary(Module, Binary) ->
    Dir = scratch_dir(Module),
    BeamPath = filename:join(Dir, atom_to_list(Module) ++ ".beam"),
    ok = filelib:ensure_dir(BeamPath),
    ok = file:write_file(BeamPath, Binary),
    case code:load_binary(Module, BeamPath, Binary) of
        {module, Module} -> {ok, Module};
        {error, Reason} -> {error, {load_failed, Reason}}
    end.

scratch_dir(Module) ->
    filename:join(?SCRATCH_ROOT, atom_to_list(Module)).
