-module(alien_mutants_reader_tests).

-include_lib("eunit/include/eunit.hrl").

%% Paths are relative to the project root (where `rebar3 eunit` runs),
%% so fixtures now live under the moved umbrella app.
-define(FIXTURES, "apps/alien_mutants/test/fixtures").

read_file_positive_test() ->
    Path = filename:join(?FIXTURES, "valid.lfe"),
    {ok, Forms} = alien_mutants_reader:read_file(Path),
    ?assert(is_list(Forms)),
    ?assertEqual(1, length(Forms)),
    [Form | _] = Forms,
    ?assert(is_list(Form)),
    ?assertEqual(defmodule, hd(Form)).

read_file_malformed_test() ->
    Path = filename:join(?FIXTURES, "malformed.lfe"),
    Result = alien_mutants_reader:read_file(Path),
    ?assertMatch({error, _}, Result),
    {error, Err} = Result,
    ?assertMatch({_, lfe_parse, _}, Err),
    ?assertEqual(lfe_parse, element(2, Err)).
