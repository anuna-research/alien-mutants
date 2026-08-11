# NOTES — CLI wiring (`rebar3 mutate`)

This work wires the five mutation-testing modules (reader, operators,
isolation, runner, report) together behind a `rebar3 mutate` provider,
per SPEC-001-lfe-mutation-testing.md's **Enable path**: it never runs
automatically as part of `rebar3 compile` / `rebar3 eunit` / any other
rebar3 command — only when the user explicitly types `rebar3 mutate`.

## Layout

The repo is now a small umbrella so rebar3 can discover the plugin *and*
still build/tests the app:

- `apps/alien_mutants/` — the library application (reader/operators/
  isolation/runner/report) plus `alien_mutants_cli`, its tests and fixtures.
- `plugins/alien_mutants/` — the rebar3 plugin: the app's `.app.src`
  registers `{env, [{providers, [rebar3_mutate_prv]}]}` and the thin
  provider module `rebar3_mutate_prv` implements `init/1`/`do/1`.
- root `rebar.config` — `{plugins, [alien_mutants]}`.

### Why the umbrella / local-plugin structure (registration mechanism)

The task asked to research the plugin-registration mechanism rather than
guess, so this is worth recording:

- A project cannot simply declare `{plugins, [alien_mutants]}` pointing at
  its own `src/`. rebar3 resolves a bare plugin name (or `{path, ...}` dep,
  which is *not* a built-in resource in rebar3 3.27) as a git/hex fetch, and
  a `{git, ...}` self-reference clones the repo — whose rebar.config then
  self-references again → infinite recursion.
- rebar3 *does* natively support **local plugins**: an umbrella project can
  put a plugin under `plugins/<name>` and rebar discovers it from
  `plugins/*` (`rebar_plugins:discover_plugins/1`). This mechanism only
  activates for umbrella projects (`rebar_plugins:is_umbrella/1` heuristics:
  no `src/` at the root, and an empty lib-dir entry). Hence the app lives
  under `apps/alien_mutants`.
- The provider module is compiled as part of the *plugin* (so it is on the
  code path in time for `providers:new/2`, which requires the module to
  exist), while the actual pipeline lives in `alien_mutants_cli` inside the
  app; `rebar3_mutate_prv:do/1` delegates to `alien_mutants_cli:do/1`.
  The provider declares `{deps, [compile]}` so the umbrella app (with its
  `lfe` dependency) is compiled and on the code path when `do/1` runs.

## Target selection

`rebar3 mutate path/to/module.lfe` mutates that file. With no argument it
scans the current project's `apps/*/src/*.lfe` and `src/*.lfe` (the
documented default for adopting projects).

## How each mutant is checked (the check function)

REQ-004 runs the project's EUnit tests against each mutant. The isolation
layer loads every mutant under a *unique* module name (REQ-003), so the
check follows `alien_mutants_runner`'s design note: the module-under-test
atom is published in a `persistent_term` slot and the fixture's `foo_tests`
EUnit module reads it (a "module atom parameter"). Each check:

1. compiles the target's `foo_tests.erl` (beside the target, or in `test/`)
   into `_build/mutants/eunit/` once;
2. sets `{alien_mutants, module_under_test}` to the loaded mutant atom;
3. runs `eunit:test([{module, FooTests}], [no_tty])` (with `[no_tty]` so the
   per-mutant EUnit chatter doesn't pollute the report);
4. returns `survived` iff the whole module still passes, `killed` iff any
   test fails. A missing/uncompilable test module yields no verdicts, so all
   mutants survive (with a warning).

Erlang test modules in `test/fixtures/` are avoided on purpose: rebar3's
eunit automatically discovers *every* `.erl` under a project's `test/` dir,
so `_tests.erl` fixtures live under `apps/alien_mutants/fixtures/` instead.

## Demonstration

Running on the "weak test" fixture (checks only the return *type*, never
the value — the SPEC-001 worked example):

```
$ rebar3 mutate apps/alien_mutants/fixtures/am_fixture_weak_math.lfe
module am_fixture_weak_math (apps/alien_mutants/fixtures/am_fixture_weak_math.lfe): mutants=1 killed=0 survived=1 errored=0 score=0.0
apps/alien_mutants/fixtures/am_fixture_weak_math.lfe:4: survived path=[2,4] original=['+',a,b] mutated=['-',a,b]
run: mutants=1 killed=0 survived=1 errored=0 score=0.0
```

The single arithmetic mutant (`+` → `-`) survives because the fixture's
test only asserts `is_integer(add(2,3))`. `alien_mutants_cli_tests` asserts
the same run reports `survived=1` against the fixture's real tests, and
`killed=1` when a value-aware check is substituted — both driving the same
code path (not shelling out to `rebar3 mutate`).
