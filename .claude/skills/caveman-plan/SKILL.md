---
name: caveman-plan
description: >
  Write an implementation plan as a repository document: scope and constraints, stack choice with
  rejected alternatives, phases with explicit done-criteria, risks with mitigations, and a release
  checklist. Plain professional prose with no filler — not caveman-speak, because the plan is a
  persisted document. Use when the user says "write an implementation plan", "plan this feature",
  "plan out", "how would we build", or invokes /caveman-plan.
---

# Write an implementation plan

Output goes in the repository, so register is **`lite`** per `caveman/SKILL.md` "Boundaries": full
sentences, articles kept, zero filler. Never caveman-speak — dropped articles in a committed document
are a defect. Apply the compression rules in `caveman-compress/SKILL.md` to the prose as you write it,
rather than writing long and trimming after.

Write to a file (`PLAN.md`, or `PLAN-<feature>.md` when one already exists), not to chat. Report the
path and the open questions when done.

## Required structure

Skip a section only when it genuinely does not apply, and say which and why in the report.

1. **Scope and constraints** — a table of constraint and rationale. A constraint without a reason gets
   argued away in three weeks.
2. **Non-goals** — what this explicitly will not do. The most commonly skipped section and the one
   that prevents the most rework.
3. **Stack or approach** — the choice, the reasons, then a table of alternatives considered with the
   reason each was rejected.
4. **Design** — one section per major component. Interfaces, data shapes, and the decisions a reader
   would otherwise have to re-derive.
5. **Repository layout** — where the code goes, and why the boundaries fall there.
6. **Phases** — ordered, each with an estimate and a `**Done when:**` line.
7. **Risks** — table of risk, severity, mitigation.
8. **Verification checklist** — checkboxes someone can actually tick.
9. **Starting order** — the first two or three concrete actions.

## Rules that make a plan usable

**Every phase ends with `**Done when:**`.** It must be observable by someone other than the author.
"Auth works" is not a criterion. "A logged-out user hitting `/admin` is redirected to `/login`, and the
integration test asserts it" is.

**Name a release line.** State which phase ships and say that later phases do not block it. A plan
without one turns into an unbounded backlog.

**Every rejected alternative carries its reason.** "Considered Postgres, rejected" is worthless six
months on. The reason is the whole value of writing it down.

**Prefer a mechanism over a promise.** When a constraint can be enforced by the build, the platform,
or CI, specify that instead of stating an intention. "No network access" is a wish; "the Android
manifest omits `INTERNET`, so the OS blocks it, and CI greps `lib/` for HTTP APIs" is a plan. Ask of
every constraint: what makes this fail loudly when someone breaks it?

**Estimates state their basis.** "5–7 days" alone is a guess wearing a number. Give the assumption:
who is working, at what availability, and what makes the range wide.

**Risks get falsifiable mitigations.** "Be careful about scope" is not a mitigation. "Release line
fixed at Phase 6, written in §7" is. If a risk has no mitigation, say so rather than inventing one.

**Checklist items are verifiable.** Each one names how it is checked — a command, a test, an artifact
to inspect, a device to try it on. "Performance is good" fails this; "cold start under 2 s on a
low-end Android device" passes.

**Flag the load-bearing decision.** Most plans have one choice that others depend on. Say which, and
say what breaks if it changes. A reader skimming needs to know where the risk concentrates.

**Record open questions as open.** An unresolved decision written as settled is worse than an
admitted gap. List them, with what would resolve each.

## Compress, but never these

Cut filler, hedging, connective fluff, restatement, and sentences that only announce structure.

Keep, even though brevity tempts otherwise:

- The reason behind a decision
- Rejected alternatives and why
- Non-goals and scope limits
- Consequences attached to warnings — the consequence is why anyone obeys
- Exact numbers, thresholds, versions, and named APIs or packages. Never generalise `FlameGame` to
  "the engine's game class" or `google_mobile_ads` to "ad SDKs"; a named identifier is greppable and a
  paraphrase is not.

Facts per line is the target. Fewer lines is not.

## Anti-patterns

| Smell | Fix |
|---|---|
| Phase with no done-criterion | Add one, observable by a third party |
| "Set up the architecture" as a phase | Name the artifacts that exist when it is finished |
| Feature list with no ordering | Order it, and name what ships first |
| Constraint asserted, not enforced | Give it a mechanism that fails loudly |
| Estimate with no stated assumption | Add who, at what availability |
| Risk table of generic engineering worries | Cut to risks specific to this design |
| Tech chosen with no alternatives listed | Add the table, with reasons for rejection |
| Design section that restates the interface twice | Keep the one a reader needs at that point |

## Boundaries

- Plans only. No implementation, no scaffolding, no dependency installs. If the plan needs a fact
  about the codebase, read the codebase — do not guess and do not start building.
- Do not invent requirements. Where the request is ambiguous, either state the assumption inline or
  list it under open questions. Never silently choose and present it as settled.
- Do not pad to look thorough. A three-phase plan for a three-phase job is correct.
- Verify claims about the current codebase before writing them down. A plan built on a wrong
  assumption about existing code is worse than no plan.
