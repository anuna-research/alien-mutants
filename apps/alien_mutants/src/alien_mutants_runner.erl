-module(alien_mutants_runner).

%% Loads each mutant (alien_mutants_operators's `{mutant, Path, Forms}`)
%% in isolation (alien_mutants_isolation) and classifies it `killed`,
%% `survived`, or `errored` per REQ-004.
%%
%% Design choice (documented per the task's "pick whichever is simpler"
%% instruction): the caller supplies a `check` function
%% `fun((atom()) -> pass | fail)`. The runner calls it with the mutant's
%% *isolated* module atom (the unique name alien_mutants_isolation loads
%% it under) rather than re-registering the mutant under the original
%% module's name. This keeps this module test-framework agnostic — the
%% caller decides what running "the test suite" against that atom means
%% (e.g. call a function directly, or run EUnit against a test module
%% written to take the module atom as a parameter) — and avoids the
%% extra failure modes of temporarily hijacking a live module name
%% (races if mutants ever run concurrently, harder cleanup on crash).

-export([run/3, classify_mutant/3]).

-type verdict() :: killed | survived | errored.
-type check_fun() :: fun((atom()) -> pass | fail).

-export_type([verdict/0, check_fun/0]).

%% run(OriginalForms, Mutants, CheckFun) -> [{Mutant, Verdict}].
%%  OriginalForms is the module's forms as alien_mutants_reader returns
%%  (used only to find the original module name); Mutants is the list
%%  alien_mutants_operators produces.
-spec run([term()], [alien_mutants_operators:mutant()], check_fun()) ->
          [{alien_mutants_operators:mutant(), verdict()}].
run(OriginalForms, Mutants, CheckFun) ->
    Module = module_name(OriginalForms),
    [classify_mutant(Module, Mutant, CheckFun) || Mutant <- Mutants].

%% classify_mutant(Module, Mutant, CheckFun) -> {Mutant, Verdict}.
%%  Builds and loads an isolated mutant from Mutant's mutated forms
%%  under original module name Module. Always unloads the mutant before
%%  returning, even on error, so no residue affects the next mutant
%%  (REQ-003).
-spec classify_mutant(atom(), alien_mutants_operators:mutant(), check_fun()) ->
          {alien_mutants_operators:mutant(), verdict()}.
classify_mutant(Module, {mutant, _Path, MutatedForms} = Mutant, CheckFun) ->
    IsolationMutant = alien_mutants_isolation:new(Module, MutatedForms, MutatedForms),
    case alien_mutants_isolation:load(IsolationMutant) of
        {error, _Reason} ->
            {Mutant, errored};
        {ok, Loaded} ->
            Verdict = case CheckFun(Loaded) of
                          pass -> survived;
                          fail -> killed
                      end,
            ok = alien_mutants_isolation:unload(Loaded),
            {Mutant, Verdict}
    end.

%% -- internal ---------------------------------------------------------

module_name(Forms) ->
    [Name] = [N || [defmodule, N | _] <- Forms],
    Name.
