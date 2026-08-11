-module(alien_mutants_cli).

%% CLI core for the `rebar3 mutate` provider (rebar3_mutate_prv delegates
%% here) and for direct invocation from EUnit tests.
%%
%% Target selection: the target is a `.lfe` source file given on the
%% command line; with no argument `default_targets/1` scans the current
%% project's `apps/*/src/` and `src/` directories for `*.lfe`, which is
%% how an adopting project would normally invoke it. Documented in the
%% README and SPEC-001's Enable path.
%%
%% Check function (documented): REQ-004 classifies each mutant by running
%% the project's EUnit tests against it. Because alien_mutants_isolation
%% loads every mutant under a *unique* module name (REQ-003), the check
%% function follows alien_mutants_runner's design note: it publishes the
%% isolated module atom where a fixture's test module can read it (a
%% persistent_term slot) and then runs that test module through eunit.
%% A module under test `foo` writes its `foo_tests` EUnit module to accept
%% a "module atom parameter" by reading this slot:
%%
%%     -define(MUT, persistent_term:get({alien_mutants, module_under_test})).
%%     value_test() -> ?assertEqual(5, (?MUT):add(2, 3)).
%%
%% The mutant is killed iff any test fails (eunit reports a non-ok
%% result), survived iff the whole module's tests still pass.

-export([do/1, default_targets/1, run/1, run/2, run_report/2]).

-define(MODULE_UNDER_TEST, {alien_mutants, module_under_test}).
-define(EUNIT_SCRATCH, "_build/mutants/eunit").

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, {module(), term()}}.
do(State) ->
    Positionals = strip_flags(rebar_state:command_args(State)),
    Targets = case Positionals of
                  [] -> default_targets(State);
                  _ -> Positionals
              end,
    case run(Targets) of
        ok ->
            {ok, State};
        {error, Reason} ->
            {error, {?MODULE, Reason}}
    end.

strip_flags([]) -> [];
strip_flags(["-" ++ _ | Rest]) -> strip_flags(Rest);
strip_flags([Arg | Rest]) -> [Arg | strip_flags(Rest)].

%% default_targets(State) -> [file:filename_all()].
%% The documented no-argument behaviour: every LFE module under the
%% project's own source directories.
-spec default_targets(rebar_state:t()) -> [file:filename_all()].
default_targets(State) ->
    Root = rebar_state:dir(State),
    Patterns = [filename:join(Root, P)
                || P <- ["src/*.lfe", "apps/*/src/*.lfe"]],
    lists:usort(lists:append([filelib:wildcard(P) || P <- Patterns])).

%% run/1 and run/2 run the full pipeline over one or more targets and
%% print the REQ-005 report to stdout.
-spec run(string() | [string()]) -> ok | {error, term()}.
run(Target) ->
    run_(Target, undefined).

-spec run(string(), alien_mutants_runner:check_fun()) -> ok | {error, term()}.
run(Target, CheckFun) ->
    run_(Target, CheckFun).

run_(Target, DefaultOrCustom) ->
    case run_report(Target, DefaultOrCustom) of
        {ok, _RunReport} -> ok;
        {error, _} = Error -> Error
    end.

%% run_report(Target, undefined | CheckFun) -> {ok, RunReport}.
%%  undefined means "use the default EUnit check against the project".
-spec run_report(string() | [string()],
                 undefined | alien_mutants_runner:check_fun()) ->
          {ok, alien_mutants_report:run_report()} | {error, term()}.
run_report(Target, DefaultOrCustom) when is_list(Target), Target =/= [] ->
    case is_list(hd(Target)) of
        true -> run_report_(Target, DefaultOrCustom);
        false -> run_report_([Target], DefaultOrCustom)
    end;
run_report(_Target, DefaultOrCustom) ->
    run_report_([], DefaultOrCustom).

run_report_(Targets, DefaultOrCustom) ->
    try
        ModuleReports =
            [begin
                 {ok, Report} = mutate_target(Target, DefaultOrCustom),
                 Report
             end || Target <- Targets],
        {RunReport, Rendering} = alien_mutants_report:aggregate(ModuleReports),
        io:put_chars([Rendering, "\n"]),
        {ok, RunReport}
    catch
        throw:{error, Reason} ->
            {error, Reason}
    end.

%% -- the pipeline ----------------------------------------------------

mutate_target(Path, undefined) ->
    case alien_mutants_reader:read_file(Path) of
        {ok, Forms} ->
            mutate_target(Path, Forms, default_check(Path, Forms));
        {error, Reason} ->
            throw({error, {read_failed, Path, Reason}})
    end;
mutate_target(Path, CheckFun) ->
    case alien_mutants_reader:read_file(Path) of
        {ok, Forms} ->
            mutate_target(Path, Forms, CheckFun);
        {error, Reason} ->
            throw({error, {read_failed, Path, Reason}})
    end.

mutate_target(Path, Forms, CheckFun) ->
    Mutants = alien_mutants_operators:arithmetic(Forms) ++
              alien_mutants_operators:comparison(Forms) ++
              alien_mutants_operators:boolean(Forms) ++
              alien_mutants_operators:constant(Forms) ++
              alien_mutants_operators:guard_negation(Forms),
    Results = alien_mutants_runner:run(Forms, Mutants, CheckFun),
    {Report, _Rendering} = alien_mutants_report:report(Path, Forms, Results),
    {ok, Report}.

%% -- default check function (real EUnit run) --------------------------

%% Compiles the target module's EUnit test module (if any) once and
%% returns a check function that runs it against a freshly loaded mutant.
default_check(Path, Forms) ->
    ensure_eunit_on_path(),
    case module_name(Forms) of
        undefined ->
            io:format("warning: no (defmodule ...) in ~ts; "
                      "all mutants will survive~n", [Path]),
            fun(_Loaded) -> pass end;
        Mod ->
            case compile_test_modules(Mod, Path) of
                {ok, TestMods} ->
                    run_eunit_check(TestMods);
                error ->
                    io:format("warning: no test module found for ~ts; "
                              "all mutants will survive~n", [Path]),
                    fun(_Loaded) -> pass end
            end
    end.

run_eunit_check(TestMods) ->
    fun(Loaded) ->
        persistent_term:put(?MODULE_UNDER_TEST, Loaded),
        try
            run_eunit(TestMods)
        after
            persistent_term:erase(?MODULE_UNDER_TEST)
        end
    end.

run_eunit(TestMods) ->
    case eunit:test([{module, M} || M <- TestMods], [no_tty]) of
        ok -> pass;
        _ -> fail
    end.

%% Find and compile the Erlang EUnit test modules that exercise the LFE
%% module `Mod`. A convention matching the fixture layout: the test module
%% for `foo` is `foo_tests`, looked for either beside the mutated source
%% or under the project's `test/` directory. Compilation goes to a
%% scratch dir so the project's own `_build` artifacts are untouched
%% (REQ-003); each module is compiled once and reused for every mutant.
compile_test_modules(Mod, Path) ->
    ModList = atom_to_list(Mod),
    Candidates = [filename:join(filename:dirname(Path), ModList ++ "_tests.erl"),
                  filename:join("test", ModList ++ "_tests.erl")],
    Existing = [C || C <- Candidates, filelib:is_file(C)],
    case Existing of
        [] ->
            error;
        _ ->
            OutDir = lists:flatten(?EUNIT_SCRATCH),
            ok = filelib:ensure_dir(filename:join(OutDir, "placeholder")),
            compile_all(Existing, OutDir)
    end.

compile_all([], _OutDir) ->
    {ok, []};
compile_all([Path | Rest], OutDir) ->
    case compile_one(Path, OutDir) of
        {ok, Mod} ->
            case compile_all(Rest, OutDir) of
                {ok, MoreMods} -> {ok, [Mod | MoreMods]};
                error -> error
            end;
        error ->
            error
    end.

compile_one(Path, OutDir) ->
    case compile:file(Path, [binary, debug_info, {outdir, OutDir}]) of
        {ok, Mod, Binary} ->
            load_one(Mod, Path, Binary);
        {ok, Mod, Binary, _Warnings} ->
            load_one(Mod, Path, Binary);
        {error, _Errors, _Warnings} ->
            io:format("warning: failed to compile test module ~ts~n", [Path]),
            error
    end.

load_one(Mod, Path, Binary) ->
    case code:load_binary(Mod, Path, Binary) of
        {module, Mod} -> {ok, Mod};
        _ -> error
    end.

ensure_eunit_on_path() ->
    case code:lib_dir(eunit) of
        {error, _} -> ok;
        EunitLibDir ->
            code:add_patha(filename:join(EunitLibDir, "ebin")),
            _ = code:ensure_loaded(eunit)
    end,
    ok.

%% -- helpers ----------------------------------------------------------

module_name(Forms) ->
    case [N || [defmodule, N | _] <- Forms] of
        [Name | _] -> Name;
        [] -> undefined
    end.