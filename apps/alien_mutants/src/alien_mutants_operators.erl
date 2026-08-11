-module(alien_mutants_operators).

-export([arithmetic/1, comparison/1, boolean/1, constant/1, guard_negation/1]).

%% A mutant is {mutant, Site, Forms}, where Site is a one-based path from
%% the raw LFE form list and Forms differs only at that path. This lets the
%% runner compile each complete, independently mutated form list directly.

-spec arithmetic([term()]) -> [mutant()].
arithmetic(Forms) ->
    mutate(Forms, fun arithmetic_replacement/2).

-spec comparison([term()]) -> [mutant()].
comparison(Forms) ->
    mutate(Forms, fun comparison_replacement/2).

-spec boolean([term()]) -> [mutant()].
boolean(Forms) ->
    mutate(Forms, fun boolean_replacement/2).

-spec constant([term()]) -> [mutant()].
constant(Forms) ->
    mutate(Forms, fun constant_replacement/2).

-spec guard_negation([term()]) -> [mutant()].
guard_negation(Forms) ->
    mutate(Forms, fun guard_replacement/2).

-type mutant() :: {mutant, [pos_integer()], [term()]}.
-type context() :: code | quoted.
-type replacement() :: none | {ok, term()}.
-type replacer() :: fun((term(), context()) -> replacement()).

-spec mutate([term()], replacer()) -> [mutant()].
mutate(Forms, Replacer) ->
    [{mutant, Path, replace_at_path(Forms, Path, Replacement)}
     || {Path, Replacement} <- sites_in_forms(Forms, Replacer)].

-spec sites_in_forms([term()], replacer()) -> [{[pos_integer()], term()}].
sites_in_forms(Forms, Replacer) ->
    sites_in_list(Forms, 1, [], Replacer, code).

-spec sites_in_term(term(), [pos_integer()], replacer(), context()) ->
          [{[pos_integer()], term()}].
sites_in_term(Term, Path, Replacer, Context) ->
    Here = case Replacer(Term, Context) of
               {ok, Replacement} -> [{Path, Replacement}];
               none -> []
           end,
    Here ++ sites_in_children(Term, Path, Replacer, Context).

-spec sites_in_children(term(), [pos_integer()], replacer(), context()) ->
          [{[pos_integer()], term()}].
sites_in_children(['quote', Term], Path, Replacer, _Context) ->
    sites_in_term(Term, Path ++ [2], Replacer, quoted);
sites_in_children(['backquote' | _], _Path, _Replacer, _Context) ->
    [];
sites_in_children(Term, Path, Replacer, Context) when is_list(Term) ->
    sites_in_list(Term, 1, Path, Replacer, Context);
sites_in_children(Term, Path, Replacer, Context) when is_tuple(Term) ->
    sites_in_list(tuple_to_list(Term), 1, Path, Replacer, Context);
sites_in_children(_Term, _Path, _Replacer, _Context) ->
    [].

-spec sites_in_list([term()], pos_integer(), [pos_integer()], replacer(), context()) ->
          [{[pos_integer()], term()}].
sites_in_list([], _Index, _Path, _Replacer, _Context) ->
    [];
sites_in_list([Term | Rest], Index, Path, Replacer, Context) ->
    sites_in_term(Term, Path ++ [Index], Replacer, Context) ++
        sites_in_list(Rest, Index + 1, Path, Replacer, Context).

-spec replace_at_path(term(), [pos_integer()], term()) -> term().
replace_at_path(_Term, [], Replacement) ->
    Replacement;
replace_at_path(Term, [Index | Rest], Replacement) when is_list(Term) ->
    replace_list_item(Term, Index, Rest, Replacement);
replace_at_path(Term, [Index | Rest], Replacement) when is_tuple(Term) ->
    list_to_tuple(replace_list_item(tuple_to_list(Term), Index, Rest, Replacement)).

-spec replace_list_item([term()], pos_integer(), [pos_integer()], term()) -> [term()].
replace_list_item(List, Index, Rest, Replacement) ->
    {Before, [Term | After]} = lists:split(Index - 1, List),
    Before ++ [replace_at_path(Term, Rest, Replacement) | After].

-spec arithmetic_replacement(term(), context()) -> replacement().
arithmetic_replacement(['+' | Tail], code) -> {ok, ['-' | Tail]};
arithmetic_replacement(['-' | Tail], code) -> {ok, ['+' | Tail]};
arithmetic_replacement(['*' | Tail], code) -> {ok, ['div' | Tail]};
arithmetic_replacement(['div' | Tail], code) -> {ok, ['*' | Tail]};
%% One-directional, matching Stryker's Remainder-to-Multiplication mutation:
%% 'rem' has no natural inverse pairing (unlike +/-, */div), so this is not
%% part of a swap pair the way the others are.
arithmetic_replacement(['rem' | Tail], code) -> {ok, ['*' | Tail]};
arithmetic_replacement(_Term, _Context) -> none.

-spec comparison_replacement(term(), context()) -> replacement().
comparison_replacement(['==' | Tail], code) -> {ok, ['/=' | Tail]};
comparison_replacement(['/=' | Tail], code) -> {ok, ['==' | Tail]};
comparison_replacement(['<' | Tail], code) -> {ok, ['>=' | Tail]};
comparison_replacement(['>=' | Tail], code) -> {ok, ['<' | Tail]};
comparison_replacement(['>' | Tail], code) -> {ok, ['=<' | Tail]};
comparison_replacement(['=<' | Tail], code) -> {ok, ['>' | Tail]};
comparison_replacement(_Term, _Context) -> none.

-spec boolean_replacement(term(), context()) -> replacement().
boolean_replacement(['and' | Tail], code) -> {ok, ['or' | Tail]};
boolean_replacement(['or' | Tail], code) -> {ok, ['and' | Tail]};
boolean_replacement(_Term, _Context) -> none.

-spec constant_replacement(term(), context()) -> replacement().
constant_replacement(0, _Context) -> {ok, 1};
constant_replacement([], _Context) -> {ok, [alien_mutants_sentinel]};
constant_replacement(true, _Context) -> {ok, false};
constant_replacement(false, _Context) -> {ok, true};
constant_replacement(_Term, _Context) -> none.

-spec guard_replacement(term(), context()) -> replacement().
guard_replacement(['when', Guard], code) -> {ok, ['when', ['not', Guard]]};
%% A multi-expression when clause is implicitly conjunctive, so expose that
%% conjunction before negating the entire guard clause.
guard_replacement(['when', FirstGuard | Rest], code) ->
    {ok, ['when', ['not', ['and', FirstGuard | Rest]]]};
guard_replacement(_Term, _Context) -> none.
