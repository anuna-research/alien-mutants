---
id: ADR-001
title: Reuse the lfe application's reader instead of writing a parser
status: accepted
---

# ADR-001: Reuse the `lfe` application's reader instead of writing a parser

**Context.** alien-mutants ([[SPEC-001-lfe-mutation-testing]]) must turn
`.lfe` source into an AST it can mutate. Two options: (a) depend on the `lfe`
OTP application and call its released reader (`lfe_io:read_file/1`), or
(b) write a bespoke LFE s-expression tokenizer/parser tailored to what
mutation needs.

**Decision.** Reuse the `lfe` application's reader (option a). This is rung 4
of the Simplicity Ladder (existing dependency) rather than rung 6 (new
abstraction), and it is the direct mechanism behind
[[SPEC-001-lfe-mutation-testing#CON-001]] and [[SPEC-001-lfe-mutation-testing#REQ-001]].

**Why not a bespoke parser.** LangSec: no ad-hoc parser at a trust boundary.
Even though `.lfe` source here is locally trusted, not adversarial, a
hand-rolled reader would inevitably diverge from the canonical grammar on
edge cases (reader macros, `#(...)` tuple syntax, quasiquote) that the `lfe`
application already handles correctly — and any divergence would make
alien-mutants mutate a *different* program than the one that actually
compiles, silently invalidating every report.

**Consequence.** alien-mutants takes a hard runtime dependency on the `lfe`
OTP application (already true for any LFE tooling); mutation operators
([[SPEC-001-lfe-mutation-testing#REQ-002]]) walk the reader's own form
representation rather than a custom AST, so operator code stays close to
LFE's actual s-expression shape instead of an alien-mutants-specific IR.
