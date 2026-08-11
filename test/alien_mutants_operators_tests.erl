-module(alien_mutants_operators_tests).

-include_lib("eunit/include/eunit.hrl").

arithmetic_operator_test() ->
    Forms = fixture(),
    Expected = replace_at_path(Forms, [2, 4], ['-', a, b]),
    assert_one_mutant(alien_mutants_operators:arithmetic(Forms), [2, 4], Expected).

comparison_operator_test() ->
    Forms = fixture(),
    Expected = replace_at_path(Forms, [3, 4], ['/=', a, b]),
    assert_one_mutant(alien_mutants_operators:comparison(Forms), [3, 4], Expected).

boolean_operator_test() ->
    Forms = fixture(),
    Expected = replace_at_path(Forms, [4, 4], ['or', a, b]),
    assert_one_mutant(alien_mutants_operators:boolean(Forms), [4, 4], Expected).

constant_operator_test() ->
    Forms = fixture(),
    Expected = replace_at_path(Forms, [5, 4], 1),
    assert_one_mutant(alien_mutants_operators:constant(Forms), [5, 4], Expected).

guard_negation_test() ->
    Forms = fixture(),
    Expected = replace_at_path(Forms, [6, 3, 2],
                               ['when', ['not', [is_integer, value]]]),
    assert_one_mutant(alien_mutants_operators:guard_negation(Forms), [6, 3, 2], Expected).

multi_guard_negation_test() ->
    Forms = [[defmodule, multi_guard],
             [defun, guarded,
              [[value], ['when', [is_integer, value], ['>', value, 0]], value]]],
    Expected = replace_at_path(Forms, [2, 3, 2],
                               ['when', ['not', ['and', [is_integer, value], ['>', value, 0]]]]),
    assert_one_mutant(alien_mutants_operators:guard_negation(Forms), [2, 3, 2], Expected).

empty_list_constant_test() ->
    {ok, EmptyList} = lfe_io:read_string("'()"),
    Forms = [[defmodule, list_constant],
             [defun, constant, [value], EmptyList]],
    Expected = replace_at_path(Forms, [2, 4, 2], [alien_mutants_sentinel]),
    assert_one_mutant(alien_mutants_operators:constant(Forms), [2, 4, 2], Expected).

operator_mapping_variants_test() ->
    Variants = [{fun alien_mutants_operators:arithmetic/1, ['-', a, b], ['+', a, b]},
                {fun alien_mutants_operators:arithmetic/1, ['*', a, b], ['div', a, b]},
                {fun alien_mutants_operators:arithmetic/1, ['div', a, b], ['*', a, b]},
                {fun alien_mutants_operators:comparison/1, ['/=', a, b], ['==', a, b]},
                {fun alien_mutants_operators:comparison/1, ['<', a, b], ['>=', a, b]},
                {fun alien_mutants_operators:comparison/1, ['>=', a, b], ['<', a, b]},
                {fun alien_mutants_operators:boolean/1, ['or', a, b], ['and', a, b]},
                {fun alien_mutants_operators:constant/1, true, false},
                {fun alien_mutants_operators:constant/1, false, true}],
    lists:foreach(fun assert_variant/1, Variants).

per_site_isolation_test() ->
    Forms = [[defun, triple, [a, b], ['+', a, b], ['+', a, b], ['+', a, b]]],
    Mutants = alien_mutants_operators:arithmetic(Forms),
    ?assertEqual([[1, 4], [1, 5], [1, 6]], [Site || {mutant, Site, _} <- Mutants]),
    Expected = [replace_at_path(Forms, [1, 4], ['-', a, b]),
                replace_at_path(Forms, [1, 5], ['-', a, b]),
                replace_at_path(Forms, [1, 6], ['-', a, b])],
    ?assertEqual(Expected, [MutatedForms || {mutant, _, MutatedForms} <- Mutants]),
    ?assertEqual([[defun, triple, [a, b], ['+', a, b], ['+', a, b], ['+', a, b]]], Forms).

quoted_call_is_not_a_site_test() ->
    ?assertEqual([], alien_mutants_operators:arithmetic([[quote, ['+', a, b]]])).

fixture() ->
    {ok, Forms} = alien_mutants_reader:read_file("test/fixtures/operators.lfe"),
    Forms.

assert_one_mutant([{mutant, Site, MutatedForms}], Site, ExpectedForms) ->
    ?assertEqual(ExpectedForms, MutatedForms),
    ?assertMatch({ok, _}, lfe_comp:forms(MutatedForms, [binary])).

assert_variant({Operator, OriginalTerm, ExpectedTerm}) ->
    [{mutant, [1], MutatedForms}] = Operator([OriginalTerm]),
    ?assertEqual([ExpectedTerm], MutatedForms).

replace_at_path(_Term, [], Replacement) ->
    Replacement;
replace_at_path(List, [Index | Rest], Replacement) ->
    {Before, [Term | After]} = lists:split(Index - 1, List),
    Before ++ [replace_at_path(Term, Rest, Replacement) | After].
