-module(rebar3_mutate_prv).

%% The rebar3 provider exposed as `rebar3 mutate`. This is the thin rebar3
%% glue layer: everything it calls is in the alien_mutants application, so
%% this module can be compiled stand-alone as a project-local plugin while
%% the actual mutation library ships with the umbrella app.
%%
%% It only ever runs when the user explicitly types `rebar3 mutate`
%% (SPEC-001 Enable path): providers are never executed by rebar3's own
%% `compile`/`eunit`/etc. command chains.

-behaviour(provider).

-export([init/1, do/1, format_error/1]).

-define(PROVIDER, 'mutate').
-define(DEPS, [compile]).
-define(OPTS, []).

%% init(State) -> {ok, State}.
%%  Registered by rebar3 via the alien_mutants app's `{providers, ...}`
%%  env key (rebar_plugins:validate_plugin/1 calls init/1 on each entry).
-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    Provider = providers:create([
        {name, ?PROVIDER},
        {module, ?MODULE},
        {bare, true},
        {deps, ?DEPS},
        {example, "rebar3 mutate [path/to/module.lfe]"},
        {opts, ?OPTS},
        {short_desc, "Run mutation testing against LFE source"},
        {desc, "Generates every mutant of the target LFE module(s) and "
               "re-runs the project's EUnit tests against each one, "
               "reporting which mutants the tests catch (killed) and "
               "which they miss (survived)."}
    ]),
    {ok, rebar_state:add_provider(State, Provider)}.

%% do(State) -> {ok, State} | {error, {module(), term()}}.
%%  Runs the mutation pipeline over the positional target(s), or over the
%%  project's own LFE sources when no target is given, and prints the
%%  REQ-005 report to stdout.
-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, {module(), term()}}.
do(State) ->
    alien_mutants_cli:do(State).

-spec format_error(term()) -> iolist().
format_error({read_failed, Path, Reason}) ->
    io_lib:format("could not read target ~ts: ~tp", [Path, Reason]);
format_error(Reason) ->
    io_lib:format("~tp", [Reason]).