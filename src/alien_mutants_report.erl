-module(alien_mutants_report).

%% REQ-005 report construction. `report/3` and `aggregate/1` return
%% `{Report, Rendering}`.
%%
%% Report is a map with these keys:
%%   * `module` and `file` identify the source module;
%%   * `mutant_count`, `killed_count`, `survived_count`, and `errored_count`
%%     are aggregate counts;
%%   * `score` is a float, or `undefined` when no mutant compiled; and
%%   * `surviving_mutants` lists maps with `path`, `file`, `line`, `original`,
%%     and `mutated` keys.
%%
%% Rendering is iodata. A module report has one module-summary line, followed by
%% one `file:line` line for each surviving mutant. An aggregate also adds a
%% run-summary line. The caller owns the output destination.

-export([aggregate/1, report/3]).

-type verdict() :: alien_mutants_runner:verdict().
-type result() :: {alien_mutants_operators:mutant(), verdict()}.
-type line_number() :: pos_integer() | undefined.
-type survivor() :: #{
    path := [pos_integer()],
    file := file:name_all(),
    line := line_number(),
    original := term(),
    mutated := term()
}.
-type report() :: #{
    module := atom() | undefined,
    file := file:name_all(),
    mutant_count := non_neg_integer(),
    killed_count := non_neg_integer(),
    survived_count := non_neg_integer(),
    errored_count := non_neg_integer(),
    score := float() | undefined,
    surviving_mutants := [survivor()]
}.
-type run_report() :: #{
    module_reports := [report()],
    mutant_count := non_neg_integer(),
    killed_count := non_neg_integer(),
    survived_count := non_neg_integer(),
    errored_count := non_neg_integer(),
    score := float() | undefined,
    surviving_mutants := [survivor()]
}.

-export_type([report/0, run_report/0]).

%% report(SourcePath, OriginalForms, Results) -> {Report, Rendering}.
%% Results is the output of alien_mutants_runner:run/3.
-spec report(file:name_all(), [term()], [result()]) -> {report(), iodata()}.
report(SourcePath, OriginalForms, Results) ->
    Counts = counts(Results),
    PathLines = source_path_lines(SourcePath, OriginalForms),
    Survivors = surviving_mutants(Results, SourcePath, OriginalForms, PathLines),
    Report = Counts#{module => module_name(OriginalForms),
                     file => SourcePath,
                     surviving_mutants => Survivors},
    {Report, render(Report)}.

%% aggregate(ModuleReports) -> {RunReport, Rendering}.
%% Combines reports created by report/3 for a complete multi-module run.
-spec aggregate([report()]) -> {run_report(), iodata()}.
aggregate(ModuleReports) ->
    {MutantCount, Killed, Survived, Errored} =
        lists:foldl(fun aggregate_counts/2, {0, 0, 0, 0}, ModuleReports),
    RunReport = (count_map(MutantCount, Killed, Survived, Errored))#{
        module_reports => ModuleReports,
        surviving_mutants => lists:append(
                               [maps:get(surviving_mutants, Report)
                                || Report <- ModuleReports])
    },
    {RunReport, render_run(RunReport)}.

%% -- aggregate report ------------------------------------------------

counts(Results) ->
    {MutantCount, Killed, Survived, Errored} =
        lists:foldl(fun count_result/2, {0, 0, 0, 0}, Results),
    count_map(MutantCount, Killed, Survived, Errored).

count_map(MutantCount, Killed, Survived, Errored) ->
    #{mutant_count => MutantCount,
      killed_count => Killed,
      survived_count => Survived,
      errored_count => Errored,
      score => score(Killed, Survived)}.

count_result({_Mutant, killed}, {MutantCount, Killed, Survived, Errored}) ->
    {MutantCount + 1, Killed + 1, Survived, Errored};
count_result({_Mutant, survived}, {MutantCount, Killed, Survived, Errored}) ->
    {MutantCount + 1, Killed, Survived + 1, Errored};
count_result({_Mutant, errored}, {MutantCount, Killed, Survived, Errored}) ->
    {MutantCount + 1, Killed, Survived, Errored + 1}.

aggregate_counts(Report, {MutantCount, Killed, Survived, Errored}) ->
    {MutantCount + maps:get(mutant_count, Report),
     Killed + maps:get(killed_count, Report),
     Survived + maps:get(survived_count, Report),
     Errored + maps:get(errored_count, Report)}.

score(Killed, Survived) ->
    case Killed + Survived of
        0 -> undefined;
        Denominator -> Killed / Denominator
    end.

surviving_mutants(Results, SourcePath, OriginalForms, PathLines) ->
    [survivor(Path, MutatedForms, SourcePath, OriginalForms, PathLines)
     || {{mutant, Path, MutatedForms}, survived} <- Results].

survivor(Path, MutatedForms, SourcePath, OriginalForms, PathLines) ->
    #{path => Path,
      file => SourcePath,
      line => line_for_path(Path, PathLines),
      original => term_at_path(OriginalForms, Path),
      mutated => term_at_path(MutatedForms, Path)}.

term_at_path(Term, []) ->
    Term;
term_at_path(Term, [Index | Rest]) when is_list(Term) ->
    term_at_path(lists:nth(Index, Term), Rest);
term_at_path(Term, [Index | Rest]) when is_tuple(Term) ->
    term_at_path(element(Index, Term), Rest).

module_name(Forms) ->
    case [Name || [defmodule, Name | _] <- Forms] of
        [Name | _] -> Name;
        [] -> undefined
    end.

%% -- source locations ------------------------------------------------

%% lfe_io:read_file/1 intentionally discards source positions. Use LFE's
%% scanner to rebuild a best-effort path-to-line index from the original source.
%% If detailed scanning cannot produce a path, lfe_io:parse_file/1 supplies the
%% enclosing top-level form line instead.
source_path_lines(SourcePath, Forms) ->
    TopLevelLines = top_level_path_lines(SourcePath),
    case scan_source(SourcePath) of
        {ok, Tokens} ->
            {DetailedLines, _RemainingTokens} = annotate_forms(Forms, Tokens),
            maps:merge(TopLevelLines, DetailedLines);
        error ->
            TopLevelLines
    end.

scan_source(SourcePath) ->
    case file:read_file(SourcePath) of
        {ok, Source} ->
            case unicode:characters_to_list(Source) of
                Characters when is_list(Characters) ->
                    case catch lfe_scan:string(Characters, 1) of
                        {ok, Tokens, _LastLine} -> {ok, Tokens};
                        _ -> error
                    end;
                _ ->
                    error
            end;
        {error, _Reason} ->
            error
    end.

top_level_path_lines(SourcePath) ->
    case lfe_io:parse_file(SourcePath) of
        {ok, FormsWithLines} ->
            top_level_path_lines(FormsWithLines, 1, #{});
        {error, _Reason} ->
            #{}
    end.

top_level_path_lines([], _Index, Lines) ->
    Lines;
top_level_path_lines([{_Form, Line} | Rest], Index, Lines) ->
    top_level_path_lines(Rest, Index + 1, Lines#{[Index] => Line}).

annotate_forms(Forms, Tokens) ->
    annotate_terms(Forms, 1, [], Tokens, #{}).

annotate_terms([], _Index, _ParentPath, Tokens, Lines) ->
    {Lines, Tokens};
annotate_terms([Term | Rest], Index, ParentPath, Tokens, Lines) ->
    Path = ParentPath ++ [Index],
    {NextLines, NextTokens} = annotate_term(Term, Path, Tokens, Lines),
    annotate_terms(Rest, Index + 1, ParentPath, NextTokens, NextLines).

annotate_term(Term, Path, [Token | Rest], Lines) when is_list(Term) ->
    case list_start_line(Token) of
        {ok, Line} ->
            Lines1 = add_line(Path, Line, Lines),
            {Lines2, AfterItems} = annotate_terms(Term, 1, Path, Rest, Lines1),
            {Lines2, drop_closing_token(AfterItems)};
        error ->
            annotate_prefix_or_leaf(Term, Path, Token, Rest, Lines)
    end;
annotate_term(Term, Path, [Token | Rest], Lines) when is_tuple(Term) ->
    case tuple_start_line(Token) of
        {ok, Line} ->
            Lines1 = add_line(Path, Line, Lines),
            {Lines2, AfterItems} = annotate_terms(tuple_to_list(Term), 1, Path,
                                                    Rest, Lines1),
            {Lines2, drop_closing_token(AfterItems)};
        error ->
            {add_line(Path, token_line(Token), Lines), Rest}
    end;
annotate_term(_Term, Path, [Token | Rest], Lines) ->
    {add_line(Path, token_line(Token), Lines), Rest};
annotate_term(_Term, _Path, [], Lines) ->
    {Lines, []}.

%% Reader prefix syntax expands into a two-element list in raw LFE forms. This
%% handling keeps token consumption aligned with later source terms.
annotate_prefix_or_leaf([Prefix, Inner], Path, Token, Rest, Lines) ->
    case prefix_line(Prefix, Token) of
        {ok, Line} ->
            Lines1 = add_line(Path, Line, Lines),
            Lines2 = add_line(Path ++ [1], Line, Lines1),
            annotate_term(Inner, Path ++ [2], Rest, Lines2);
        error ->
            {add_line(Path, token_line(Token), Lines), Rest}
    end;
annotate_prefix_or_leaf(_Term, Path, Token, Rest, Lines) ->
    {add_line(Path, token_line(Token), Lines), Rest}.

list_start_line({'(', Line}) ->
    {ok, Line};
list_start_line({'[', Line}) ->
    {ok, Line};
list_start_line(_Token) ->
    error.

tuple_start_line({'#(', Line}) ->
    {ok, Line};
tuple_start_line(_Token) ->
    error.

prefix_line(Prefix, {Token, Line}) ->
    case Token =:= prefix_token(Prefix) of
        true -> {ok, Line};
        false -> error
    end;
prefix_line(_Prefix, _Token) ->
    error.

prefix_token(quote) ->
    list_to_atom([$']);
prefix_token(backquote) ->
    list_to_atom([$`]);
prefix_token(comma) ->
    list_to_atom([$,]);
prefix_token('comma-at') ->
    list_to_atom([$,,$@]);
prefix_token(_Prefix) ->
    undefined.

drop_closing_token([{')', _Line} | Rest]) ->
    Rest;
drop_closing_token([{']', _Line} | Rest]) ->
    Rest;
drop_closing_token(Tokens) ->
    Tokens.

token_line(Token) when is_tuple(Token), tuple_size(Token) >= 2,
                      is_integer(element(2, Token)) ->
    element(2, Token);
token_line(_Token) ->
    undefined.

add_line(_Path, undefined, Lines) ->
    Lines;
add_line(Path, Line, Lines) ->
    Lines#{Path => Line}.

line_for_path([], _PathLines) ->
    undefined;
line_for_path(Path, PathLines) ->
    case maps:find(Path, PathLines) of
        {ok, Line} -> Line;
        error -> line_for_path(parent_path(Path), PathLines)
    end.

parent_path([_Index]) ->
    [];
parent_path(Path) ->
    lists:sublist(Path, length(Path) - 1).

%% -- rendering -------------------------------------------------------

render(Report) ->
    [render_summary(Report),
     [render_survivor(Survivor) || Survivor <- maps:get(surviving_mutants, Report)]].

render_run(RunReport) ->
    [[render(ModuleReport) || ModuleReport <- maps:get(module_reports, RunReport)],
     render_run_summary(RunReport)].

render_summary(Report) ->
    io_lib:format("module ~tp (~ts): mutants=~B killed=~B survived=~B errored=~B score=~ts~n",
                  [maps:get(module, Report),
                   display_path(maps:get(file, Report)),
                   maps:get(mutant_count, Report),
                   maps:get(killed_count, Report),
                   maps:get(survived_count, Report),
                   maps:get(errored_count, Report),
                   score_text(maps:get(score, Report))]).

render_run_summary(RunReport) ->
    io_lib:format("run: mutants=~B killed=~B survived=~B errored=~B score=~ts~n",
                  [maps:get(mutant_count, RunReport),
                   maps:get(killed_count, RunReport),
                   maps:get(survived_count, RunReport),
                   maps:get(errored_count, RunReport),
                   score_text(maps:get(score, RunReport))]).

render_survivor(Survivor) ->
    io_lib:format("~ts:~ts: survived path=~0tp original=~0tp mutated=~0tp~n",
                  [display_path(maps:get(file, Survivor)),
                   line_text(maps:get(line, Survivor)),
                   maps:get(path, Survivor),
                   maps:get(original, Survivor),
                   maps:get(mutated, Survivor)]).

display_path(Path) when is_binary(Path) ->
    unicode:characters_to_list(Path);
display_path(Path) when is_list(Path) ->
    Path;
display_path(Path) ->
    io_lib:format("~tp", [Path]).

line_text(Line) when is_integer(Line) ->
    integer_to_list(Line);
line_text(undefined) ->
    "unknown".

score_text(undefined) ->
    "undefined (no killed or survived mutants)";
score_text(Score) ->
    io_lib:format("~tp", [Score]).
