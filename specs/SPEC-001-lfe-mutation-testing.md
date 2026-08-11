---
id: SPEC-001
title: alien-mutants — Mutation Testing for Lisp Flavoured Erlang
status: implemented
tier: 3
author: anuna-02 + claude
last-updated: 2026-08-11
---

# SPEC-001: alien-mutants — Mutation Testing for Lisp Flavoured Erlang

## Orientation

`alien-mutants` is a [[rebar3]] plugin and standalone escript that mutation-tests
[[LFE]] (Lisp Flavoured Erlang) code. Point it at a project's `src/*.lfe` and it
answers one question a coverage report cannot: does the test suite actually
*notice* when the code changes meaning, not merely when it runs?

**How it works, concretely.** Given `(defun add (a b) (+ a b))` and a test
`(is-equal 4 (add 2 2))`, alien-mutants parses the form with the [[LFE Reader]],
finds the `+` head, and generates a **mutant**: the same form with `+` replaced
by `-` per the [[Arithmetic Operator Replacement]] operator
([[#REQ-002]]). It compiles the mutant module in an isolated build directory,
re-runs the project's existing [[EUnit]] suite against it, and classifies the
outcome ([[#REQ-004]]): the suite fails → the mutant is **killed** (the test
suite would have caught this regression); the suite passes unchanged → the
mutant **survives** (a real gap: nothing would have caught `-` shipping instead
of `+`). The **mutation score** ([[#REQ-005]]) is killed / (killed + survived),
reported per-module and project-wide, with every surviving mutant's file, line,
and original-vs-mutated form printed so a human can decide whether to add a
test or accept the gap.

**Concrete case a reader should be able to predict:** a module with one function
and one test that only checks the *type* of the return value (`(is (is_integer
(add 2 2)))`, never the value) — alien-mutants mutates `+` to `-`, `add(2,2)`
still returns an integer, the suite still passes, the mutant survives, and the
report names that exact line as unverified. A REQ-driven coverage tool would
call this line 100% covered; alien-mutants calls it 0% mutation-killed. That
gap is the entire reason this tool exists over `rebar3 cover` ([[#REQ-001]]
names the failure this addresses).

**What decides "was this REQ met":** [[#TEST-001]] through [[#TEST-005]], one
per REQ, each with a positive case (mutant killed/survived correctly) and a
negative case (an input the recogniser must reject or a mutant it must not
silently skip). [[#CON-001]] is the input-boundary contract: alien-mutants reads
only well-formed LFE source through the LFE reader itself — never a hand-rolled
parser — so malformed input is rejected before any mutation logic runs.

## Named failure mode

**What is mechanically going wrong today:** LFE has no mutation testing tool.
Erlang has `mutation_test` (unmaintained, targets pure Erlang ASTs — cannot read
LFE's s-expression source) and `cover`/`eunit` report line/branch coverage,
which measures *execution*, not *verification*. A test suite can execute every
line of an LFE module and verify almost none of its behaviour — assertions
that check "no crash" or "right type" rather than "right value" pass under
coverage tooling and hide real regressions until production. Teams writing LFE
today have no automated way to find these gaps; the alternative is manual
code review of every assertion, which does not scale and misses exactly the
cases a reviewer's attention slides past.

## Scope and tier

**Tier 3** (standard feature code, per [[PROTO-001-usdd-agent-protocol#Pick the tier before you start]]):
this is a new developer tool, not a no-go area, not handling untrusted network
input, not core business logic of an existing system. It reads local source
files the developer already trusts and controls, and writes to a scratch build
directory. Escalation trigger check: alien-mutants does **not** write a hand-rolled
parser for LFE — [[#CON-001]] mandates reading through the `lfe` OTP
application's own reader, so the Tier 1–2 "hand-rolled external-format parser"
trigger does not apply. Same-model fresh-context review (Tier 3's minimum) is
REQUIRED before [[#REQ-001]]–[[#REQ-005]] are marked `completed`.

## Requirements

### REQ-001: Parse LFE source via the LFE reader, never a bespoke parser

alien-mutants MUST obtain module ASTs by invoking the `lfe` application's own
reader/compiler front end (`lfe_io:read_file/1` or equivalent released API),
never a hand-written LFE tokenizer or s-expression parser.

**Trace:** named failure mode above (no LFE-aware tooling exists); also the
LangSec invariant — no ad-hoc parser at a trust boundary — even though this
input is locally trusted, reuse of the canonical reader is what makes
[[#REQ-002]]'s mutations round-trip losslessly (comments/macros the reader
already resolves correctly).

**Acceptance:** given a syntactically valid `.lfe` file, alien-mutants produces
the same parsed forms `lfe_io:read_file/1` would; given a malformed file, it
reports the reader's own error location and performs no mutation.

### REQ-002: Mutation operator set

alien-mutants MUST implement, at minimum, these operators, each independently
selectable:

| Operator | Example |
|---|---|
| [[Arithmetic Operator Replacement]] | `+` ↔ `-`, `*` ↔ `div` |
| [[Comparison Operator Replacement]] | `==` ↔ `/=`, `<` ↔ `>=` |
| [[Boolean Operator Replacement]] | `and` ↔ `or` |
| [[Constant Replacement]] | `0` → `1`, `[]` → non-empty sentinel, `true`/`false` swap |
| [[Guard Negation]] | negate a `when` guard clause |

Each operator MUST generate one mutant per matching site (not one mutant for
the whole module), so a module with three `+` sites yields three independent
mutants.

**Trace:** [[#Named failure mode]] — this set covers the categories of silent
value-vs-execution divergence a coverage tool cannot see.

**Acceptance:** a fixture module with one instance of each operator's target
form produces exactly one mutant per site, each a minimal one-token diff from
the original.

### REQ-003: Isolated per-mutant compilation

Each mutant MUST be compiled and executed in a location that cannot corrupt
the original `_build` artifacts or leave residue that affects the next
mutant's run (fresh BEAM module load, unique module name or unique code path
per mutant).

**Trace:** correctness precondition for [[#REQ-004]] — a shared build directory
would let one mutant's stale `.beam` file produce a false kill/survive verdict
for the next.

**Acceptance:** running the full mutant set twice in a row, in different
process-scheduling order, produces byte-identical kill/survive verdicts.

### REQ-004: Kill/survive classification against the project's existing test suite

For each mutant, alien-mutants MUST run the project's existing EUnit suite
(via `rebar3 eunit` or the equivalent `eunit:test/1` call) against the mutated
module and classify the mutant `killed` (suite reports a failure) or
`survived` (suite passes) or `errored` (mutant fails to compile — reported
separately, not counted as killed, since a compile error is not evidence the
*test suite* would catch a semantically-valid-but-wrong mutation).

**Trace:** [[#Named failure mode]] directly — this is the verification signal
coverage tools lack.

**Acceptance:** the fixture from [[#REQ-002]]'s acceptance, run against a test
that only checks return type, classifies the arithmetic mutant `survived`; run
against a test that checks the return value, classifies it `killed`.

### REQ-005: Mutation score report

alien-mutants MUST report, per module and aggregated for the run: mutant
count, killed count, survived count, errored count, and
`score = killed / (killed + survived)` (errored mutants excluded from the
denominator per [[#REQ-004]]). Every survived mutant MUST be printed with file,
line, original form, and mutated form.

**Trace:** [[#Named failure mode]] — the score is the actionable output; a
raw kill/survive list without file:line is not something a developer can act
on.

**Acceptance:** the two-test fixture from [[#REQ-004]] produces a report
naming the surviving arithmetic mutant's exact file and line.

## Non-functional requirements

### NFR-001: Mutant run time bounded by test suite time, not combinatorial blowup

For a project with N mutation sites and a test suite that takes T seconds,
a full run MUST complete in `O(N * T)` wall time in the default (serial)
mode, with an opt-in parallel mode ([[#Open: parallel execution]]) deferred
as depth, not core.

**Trace:** a tool that takes hours makes mutation testing something a team
runs once and abandons, not something run in CI — reintroducing the named
failure mode by disuse rather than by absence.

## Contracts

### CON-001: LFE source input boundary

**Grammar:** delegated entirely to the `lfe` application's own reader grammar
(LFE s-expression syntax, as defined by the `lfe` OTP application's released
parser) — alien-mutants defines no grammar of its own for this boundary.
**Full recognition before semantic action:** a file is accepted only if
`lfe_io:read_file/1` (or equivalent) returns a complete, error-free form list;
partial/recovered parses are never mutated.

**Trace:** [[#REQ-001]].

## Tests (core / depth split)

**Core** — an implementer writes these in one sitting, no rig needed:

- [[#TEST-001]] (REQ-001, positive): valid `.lfe` fixture parses to the expected
  form list.
- [[#TEST-001]] (REQ-001, negative-input): malformed `.lfe` fixture is rejected
  with the reader's error, zero mutants generated.
- [[#TEST-002]] (REQ-002, positive): one-site-per-operator fixture yields
  exactly the expected mutant set.
- [[#TEST-003]] (REQ-003, positive): two sequential full runs produce
  identical verdicts.
- [[#TEST-004]] (REQ-004, positive): type-only-assertion fixture → `survived`;
  value-assertion fixture → `killed`.
- [[#TEST-004]] (REQ-004, negative-output): a mutant that fails to compile is
  reported `errored`, not counted in the score denominator.
- [[#TEST-005]] (REQ-005, positive): report names the exact file:line of the
  one surviving mutant in the [[#REQ-004]] fixture.

**Depth** — needs a real multi-module rebar3 project fixture, deferred with
owner `claude` via troupe (see [[#Open: parallel execution]]):

- Mutation score computed correctly across a multi-module project with mixed
  killed/survived/errored mutants.
- [[#NFR-001]]'s time-bound, measured against a real project's suite.

## Enable path

alien-mutants is a new, standalone tool with no existing deployment to
protect — there is no traffic to shadow-mode or roll back. The enable path is
therefore: install as a `rebar3` plugin (`{plugins, [alien_mutants]}` in
`rebar.config`), invoke explicitly (`rebar3 mutate`); it never runs
automatically in a build or CI step unless the adopting project wires it in.
Uninstall = remove the plugin line. No kill switch is needed because nothing
is ever on by default.

## Open

- **Open: parallel execution** — NFR-001 names serial `O(N*T)` as the
  contractual bound; a parallel mode is useful but deferred as depth, no
  owner assigned yet.
- **Open: mutation operator extensibility** — whether third parties can
  register custom operators (rung-6 abstraction) is deferred until REQ-002's
  fixed set proves insufficient in practice (Simplicity Ladder: don't build
  the extension point speculatively).

## Comprehension gate record

Fresh-context read of the Orientation alone (self-administered, Tier 3 — see
[[#Scope and tier]]): restated intent — "mutate LFE source and see if the
existing tests notice" — correctly predicted the type-only-assertion/survives
vs value-assertion/kills outcome for the worked example, and named
[[#TEST-004]] as the artefact deciding it. Gate: **pass**. Independent
cross-model re-check deferred to Phase 3 pre-`completed` review per the Tier 3
minimum above.
