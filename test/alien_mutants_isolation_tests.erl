-module(alien_mutants_isolation_tests).

-include_lib("eunit/include/eunit.hrl").

%% Tiny fixture module, defined inline as LFE forms (module attributes
%% and function definitions are separate top-level forms, per LFE
%% syntax): (defmodule sample (export (add 2))) (defun add (a b) (+ a b))
%%
%% Two fake mutants derived from it: one unmutated ("plus"), one with
%% the Arithmetic Operator Replacement operator applied by hand
%% ("minus", a - b instead of a + b). Running both, twice, in reverse
%% order the second time, must classify identically both times.

module_form() ->
    [defmodule, sample, [export, [add, 2]]].

plus_defun_form() ->
    [defun, add, [a, b], ['+', a, b]].

minus_defun_form() ->
    [defun, add, [a, b], ['-', a, b]].

two_runs_produce_identical_verdicts_test() ->
    PlusMutant = alien_mutants_isolation:new(
        sample, [module_form(), plus_defun_form()], plus_defun_form()
    ),
    MinusMutant = alien_mutants_isolation:new(
        sample, [module_form(), minus_defun_form()], plus_defun_form()
    ),
    Labelled = [{plus, PlusMutant}, {minus, MinusMutant}],

    Run1 = run_all(Labelled),
    Run2 = run_all(lists:reverse(Labelled)),

    ?assertEqual([{minus, -1}, {plus, 5}], lists:sort(Run1)),
    ?assertEqual(lists:sort(Run1), lists:sort(Run2)).

run_all(Labelled) ->
    [{Label, run_mutant(Mutant)} || {Label, Mutant} <- Labelled].

run_mutant(Mutant) ->
    {ok, Loaded} = alien_mutants_isolation:load(Mutant),
    Value = Loaded:add(2, 3),
    ok = alien_mutants_isolation:unload(Loaded),
    Value.
