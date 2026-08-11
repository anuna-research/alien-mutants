-module(am_fixture_weak_math_tests).

%% EUnit test module for the am_fixture_weak_math fixture (REQ-004).
%%
%% Deliberately WEAK: it only checks the *type* of add/2's result, never
%% its value, so the `+` -> `-` arithmetic mutant survives (both return an
%% integer). This is the SPEC-001 worked example: coverage would call the
%% line 100% covered; mutation testing reports it survived.
%%
%% The module-under-test atom is taken from the {alien_mutants,
%% module_under_test} persistent_term slot that alien_mutants_cli sets for
%% the duration of each mutant's check run (the isolation layer loads
%% every mutant under a unique module name, so the test accepts the module
%% atom as a parameter rather than hard-coding it).

-include_lib("eunit/include/eunit.hrl").

-define(MUT, persistent_term:get({alien_mutants, module_under_test})).

add_returns_integer_test() ->
    Mod = ?MUT,
    ?assert(is_integer(Mod:add(2, 3))).