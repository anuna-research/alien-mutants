-module(alien_mutants_cli_tests).

-include_lib("eunit/include/eunit.hrl").

%% Exercises alien_mutants_cli (the module behind rebar3_mutate_prv's
%% do/1) directly, not by shelling out to `rebar3 mutate`. The fixture is
%% am_fixture_weak_math: (defun add (a b) (+ a b)) with a deliberately
%% type-only EUnit test, so the single arithmetic mutant must survive
%% against the fixture's real test suite and be killed by a value check.

fixture() ->
    "apps/alien_mutants/fixtures/am_fixture_weak_math.lfe".

weak_default_check_survives_test() ->
    %% Uses the real EUnit check (undefined = "project's own tests") like
    %% `rebar3 mutate` does. The fixture's test only asserts the return
    %% type, so `+` -> `-` survives.
    {ok, Report} = alien_mutants_cli:run_report(fixture(), undefined),
    ?assertEqual(1, maps:get(mutant_count, Report)),
    ?assertEqual(0, maps:get(killed_count, Report)),
    ?assertEqual(1, maps:get(survived_count, Report)),
    ?assertEqual(0, maps:get(errored_count, Report)),
    ?assertEqual(0.0, maps:get(score, Report)),
    [Survivor] = maps:get(surviving_mutants, Report),
    ?assertEqual(fixture(), maps:get(file, Survivor)),
    ?assertMatch([_ | _], maps:get(path, Survivor)),
    ?assert(is_integer(maps:get(line, Survivor))).

value_check_kills_test() ->
    %% A value-aware check (the would-be "strong" test for REQ-004)
    %% catches the mutation, so the same fixture is reported killed.
    Check = fun(Mod) ->
        case Mod:add(2, 3) =:= 5 of
            true -> pass;
            false -> fail
        end
    end,
    {ok, Report} = alien_mutants_cli:run_report(fixture(), Check),
    ?assertEqual(1, maps:get(mutant_count, Report)),
    ?assertEqual(1, maps:get(killed_count, Report)),
    ?assertEqual(0, maps:get(survived_count, Report)),
    ?assertEqual(0, maps:get(errored_count, Report)),
    ?assertEqual([], maps:get(surviving_mutants, Report)).

do_provider_pipeline_test() ->
    %% Drives rebar3_mutate_prv's do/1 (via alien_mutants_cli:do/1) with a
    %% rebar_state carrying the fixture as its positional argument. Only
    %% meaningful when a rebar3 process is running our eunit.
    case code:which(rebar_state) of
        non_existing ->
            ok;
        _ ->
            State = rebar_state:new(),
            State1 = rebar_state:command_args(State, [fixture()]),
            ?assertMatch({ok, _}, alien_mutants_cli:do(State1))
    end.

missing_target_errors_test() ->
    ?assertMatch({error, {read_failed, _, _}},
                 alien_mutants_cli:run_report("test/fixtures/does_not_exist.lfe",
                                              fun(_Mod) -> pass end)).