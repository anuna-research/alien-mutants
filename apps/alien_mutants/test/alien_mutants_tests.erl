-module(alien_mutants_tests).

-include_lib("eunit/include/eunit.hrl").

version_test() ->
    ?assertEqual("0.1.0", alien_mutants:version()).
