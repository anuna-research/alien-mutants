-module(alien_mutants_runner_tests).

-include_lib("eunit/include/eunit.hrl").

%% Fixture: (defmodule sample (export (add 2))) (defun add (a b) (+ a b))
%% Mutating the `+` gives one arithmetic-swap mutant (a - b instead of
%% a + b). A "check" that only inspects the return *type* cannot tell
%% the two apart (both return integers) -> the mutant must survive. A
%% "check" that inspects the return *value* can -> the mutant must be
%% killed.

fixture() ->
    [[defmodule, sample, [export, [add, 2]]],
     [defun, add, [a, b], ['+', a, b]]].

arithmetic_mutant() ->
    [Mutant] = alien_mutants_operators:arithmetic(fixture()),
    Mutant.

type_only_check_survives_test() ->
    Check = fun(Mod) ->
        case is_integer(Mod:add(2, 3)) of
            true -> pass;
            false -> fail
        end
    end,
    ?assertEqual([{arithmetic_mutant(), survived}],
                 alien_mutants_runner:run(fixture(), [arithmetic_mutant()], Check)).

value_check_kills_test() ->
    Check = fun(Mod) ->
        case Mod:add(2, 3) =:= 5 of
            true -> pass;
            false -> fail
        end
    end,
    ?assertEqual([{arithmetic_mutant(), killed}],
                 alien_mutants_runner:run(fixture(), [arithmetic_mutant()], Check)).

invalid_mutant_errors_test() ->
    BadMutant = {mutant, [2], [[defmodule, sample], [defun, add, not_a_list, ['+', a, b]]]},
    Check = fun(_Mod) -> pass end,
    ?assertEqual([{BadMutant, errored}],
                 alien_mutants_runner:run(fixture(), [BadMutant], Check)).
