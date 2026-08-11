# alien-mutants

Mutation testing for [Lisp Flavoured Erlang](https://lfe.io) (LFE). Point it
at an `.lfe` module and it answers a question code coverage cannot: does the
test suite actually notice when the code's *meaning* changes, not just when
it runs?

See [`specs/SPEC-001-lfe-mutation-testing.md`](specs/SPEC-001-lfe-mutation-testing.md)
for the full design (requirements, contracts, and the failure mode this
addresses) and [`specs/ADR-001-reuse-lfe-reader.md`](specs/ADR-001-reuse-lfe-reader.md)
for why source is read through LFE's own reader rather than a bespoke parser.

## Install

Add the plugin to a project's `rebar.config`:

```erlang
{plugins, [alien_mutants]}.
```

`rebar3 mutate` never runs as part of `compile`, `eunit`, or any other
rebar3 command — only when invoked explicitly.

## Use

```console
$ rebar3 mutate path/to/module.lfe
module my_module (path/to/module.lfe): mutants=6 killed=5 survived=1 errored=0 score=0.833
path/to/module.lfe:12: survived path=[3,4] original=['+',a,b] mutated=['-',a,b]
run: mutants=6 killed=5 survived=1 errored=0 score=0.833
```

With no argument, it scans the project's own `src/*.lfe` and
`apps/*/src/*.lfe` for every LFE module and reports on all of them.

The default classifier compiles and runs the target module's EUnit test
module (`<module>_tests.erl`, found beside the source or under `test/`)
against each mutant, isolated under a unique module name so no mutant run
can affect another. A test module that wants to exercise the specific
mutant instance under test (rather than always calling the original module
name) reads it from a `persistent_term` slot:

```erlang
-define(MUT, persistent_term:get({alien_mutants, module_under_test})).
value_test() -> ?assertEqual(5, (?MUT):add(2, 3)).
```

A mutant is **killed** if any test in that module fails against it,
**survived** if the whole suite still passes unchanged, and **errored** if
it fails to compile (excluded from the score, since a compile error is not
evidence the *test suite* would catch a semantically-wrong mutation).

## Mutation operators

| Operator | Example |
|---|---|
| Arithmetic Operator Replacement | `+` ↔ `-`, `*` ↔ `div` |
| Comparison Operator Replacement | `==` ↔ `/=`, `<` ↔ `>=` |
| Boolean Operator Replacement | `and` ↔ `or` |
| Constant Replacement | `0` → `1`, `[]` → non-empty sentinel, `true`/`false` swap |
| Guard Negation | negate a `when` guard clause |

Each generates one independent mutant per matching call site — a module
with three `+` sites yields three mutants, not one. Mutation inside quoted
(`'`) or backquoted data is never treated as a site.

## Architecture

```
alien_mutants_reader      parse .lfe source via the lfe application's own reader (REQ-001)
alien_mutants_operators   generate mutants: one per operator per site (REQ-002)
alien_mutants_isolation   compile/load one mutant under a unique module name (REQ-003)
alien_mutants_runner      classify killed / survived / errored (REQ-004)
alien_mutants_report      per-module + aggregate score and rendering (REQ-005)
alien_mutants_cli         rebar3 mutate wiring (Enable path)
```

`alien_mutants_cli` composes the five library modules; it lives in the
`plugins/alien_mutants` app (rebar3 only auto-discovers local plugins in
umbrella-style projects, which is why the library itself lives under
`apps/alien_mutants` rather than a flat `src/`).

## Develop

```console
$ rebar3 eunit    # 27 tests
$ rebar3 compile
```

Each module's test suite exercises both directions of every operator
mapping and includes at least one negative case (malformed input rejected,
a mutant that fails to compile classified `errored` and excluded from the
score) per [`SPEC-001`](specs/SPEC-001-lfe-mutation-testing.md)'s
TEST-001–TEST-005.
