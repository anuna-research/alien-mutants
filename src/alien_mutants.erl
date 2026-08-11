-module(alien_mutants).

-export([version/0]).

version() ->
    application:load(alien_mutants),
    {ok, Vsn} = application:get_key(alien_mutants, vsn),
    Vsn.
