-module(alien_mutants_report_tests).

-include_lib("eunit/include/eunit.hrl").

report_lists_surviving_mutant_at_its_source_line_test() ->
    SourcePath = "apps/alien_mutants/test/fixtures/report.lfe",
    {ok, Forms} = alien_mutants_reader:read_file(SourcePath),
    [Mutant] = alien_mutants_operators:arithmetic(Forms),
    Killed = alien_mutants_runner:run(Forms, [Mutant], value_check()),
    Survived = alien_mutants_runner:run(Forms, [Mutant], type_only_check()),

    {Report, Rendering} = alien_mutants_report:report(SourcePath, Forms,
                                                        Killed ++ Survived),

    ?assertEqual(2, maps:get(mutant_count, Report)),
    ?assertEqual(1, maps:get(killed_count, Report)),
    ?assertEqual(1, maps:get(survived_count, Report)),
    ?assertEqual(0, maps:get(errored_count, Report)),
    ?assertEqual(0.5, maps:get(score, Report)),
    [Survivor] = maps:get(surviving_mutants, Report),
    ?assertEqual(SourcePath, maps:get(file, Survivor)),
    ?assertEqual(3, maps:get(line, Survivor)),
    ?assertEqual(['+', a, b], maps:get(original, Survivor)),
    ?assertEqual(['-', a, b], maps:get(mutated, Survivor)),
    ?assertMatch({_, _}, binary:match(iolist_to_binary(Rendering),
                                      <<"apps/alien_mutants/test/fixtures/report.lfe:3">>)),
    RenderedLines = [Line || Line <- string:split(iolist_to_binary(Rendering),
                                                   <<"\n">>, all),
                             Line =/= <<>>],
    ?assertEqual(2, length(RenderedLines)).

undefined_score_excludes_errored_mutants_test() ->
    Forms = [[defmodule, sample], [defun, add, [a, b], ['+', a, b]]],
    Mutant = {mutant, [2, 4], [[defmodule, sample],
                               [defun, add, [a, b], ['-', a, b]]]},

    {Report, Rendering} = alien_mutants_report:report("sample.lfe", Forms,
                                                        [{Mutant, errored}]),

    ?assertEqual(1, maps:get(mutant_count, Report)),
    ?assertEqual(0, maps:get(killed_count, Report)),
    ?assertEqual(0, maps:get(survived_count, Report)),
    ?assertEqual(1, maps:get(errored_count, Report)),
    ?assertEqual(undefined, maps:get(score, Report)),
    ?assertMatch({_, _}, binary:match(iolist_to_binary(Rendering),
                                      <<"score=undefined">>)).

killed_only_score_is_one_test() ->
    SourcePath = "apps/alien_mutants/test/fixtures/report.lfe",
    {ok, Forms} = alien_mutants_reader:read_file(SourcePath),
    [Mutant] = alien_mutants_operators:arithmetic(Forms),

    {Report, _Rendering} = alien_mutants_report:report(SourcePath, Forms,
                                                         [{Mutant, killed}]),

    ?assertEqual(1.0, maps:get(score, Report)).

errored_mutants_do_not_reduce_the_score_test() ->
    SourcePath = "apps/alien_mutants/test/fixtures/report.lfe",
    {ok, Forms} = alien_mutants_reader:read_file(SourcePath),
    [Mutant] = alien_mutants_operators:arithmetic(Forms),

    {Report, _Rendering} = alien_mutants_report:report(SourcePath, Forms,
                                                         [{Mutant, killed},
                                                          {Mutant, survived},
                                                          {Mutant, errored}]),

    ?assertEqual(3, maps:get(mutant_count, Report)),
    ?assertEqual(1, maps:get(errored_count, Report)),
    ?assertEqual(0.5, maps:get(score, Report)).

quasiquote_before_mutant_does_not_shift_its_source_line_test() ->
    SourcePath = "apps/alien_mutants/test/fixtures/report_with_quasiquote.lfe",
    {ok, Forms} = alien_mutants_reader:read_file(SourcePath),
    [Mutant] = alien_mutants_operators:arithmetic(Forms),

    {Report, _Rendering} = alien_mutants_report:report(SourcePath, Forms,
                                                         [{Mutant, survived}]),

    [Survivor] = maps:get(surviving_mutants, Report),
    ?assertEqual(4, maps:get(line, Survivor)).

aggregate_combines_module_reports_test() ->
    SourcePath = "apps/alien_mutants/test/fixtures/report.lfe",
    {ok, Forms} = alien_mutants_reader:read_file(SourcePath),
    [Mutant] = alien_mutants_operators:arithmetic(Forms),
    {KilledReport, _} = alien_mutants_report:report(SourcePath, Forms,
                                                      [{Mutant, killed}]),
    {SurvivedReport, _} = alien_mutants_report:report(SourcePath, Forms,
                                                        [{Mutant, survived}]),

    {RunReport, Rendering} = alien_mutants_report:aggregate([KilledReport,
                                                               SurvivedReport]),

    ?assertEqual(2, maps:get(mutant_count, RunReport)),
    ?assertEqual(1, maps:get(killed_count, RunReport)),
    ?assertEqual(1, maps:get(survived_count, RunReport)),
    ?assertEqual(0, maps:get(errored_count, RunReport)),
    ?assertEqual(0.5, maps:get(score, RunReport)),
    ?assertMatch({_, _}, binary:match(iolist_to_binary(Rendering),
                                      <<"run: mutants=2 killed=1 survived=1 errored=0 score=0.5">>)).

type_only_check() ->
    fun(Mod) ->
        case is_integer(Mod:add(2, 3)) of
            true -> pass;
            false -> fail
        end
    end.

value_check() ->
    fun(Mod) ->
        case Mod:add(2, 3) =:= 5 of
            true -> pass;
            false -> fail
        end
    end.
