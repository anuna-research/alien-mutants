-module(alien_mutants_reader).

-export([read_file/1]).

-spec read_file(file:name_all()) ->
          {ok, [term()]} | {error, term()}.
read_file(Path) ->
    lfe_io:read_file(Path).
