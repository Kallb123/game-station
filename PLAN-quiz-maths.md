# Quiz maths: generated arithmetic questions

> **Closed.** Built in one pull request; what differed from the plan is in §11. The *(Device)*
> lines in §8 are open.

The quiz (`PLAN-phase-10-quiz.md`) asks questions written into JSON packs and checked by a person. The
owner asked for a Maths topic that is **not a bank of questions**: a child chooses which operations
to practise — adding, taking away, times tables, dividing — and which times tables they know, and the
quiz generates a round from that.

This plan adds Maths as a fourth way into the Quiz menu, beside *Quiz me*, *Pick one* and *My shelf*,
played on the existing play screen. It is one pull request. **The release line is that pull
request**; nothing in §9 blocks it.

**Contents:**
[1 Scope and constraints](#1-scope-and-constraints) ·
[2 Non-goals](#2-non-goals) ·
[3 Approach](#3-approach) ·
[4 Design](#4-design) ·
[5 Repository layout](#5-repository-layout) ·
[6 Phases](#6-phases) ·
[7 Risks](#7-risks) ·
[8 Verification checklist](#8-verification-checklist) ·
[9 Open questions](#9-open-questions) ·
[10 Starting order](#10-starting-order) ·
[11 Outcome](#11-outcome)

---

## 1. Scope and constraints

| Constraint | Rationale and mechanism |
|---|---|
| Questions are generated, never stored | The ask. A bank of sums is thousands of entries a person would have to check, and still could not follow a child's own choice of tables. The save holds the child's settings and two counters, never a question (§4.4). |
| Every generated answer is right | `PLAN-phase-10-quiz.md` §1's first constraint is that a wrong "right answer" never reaches a child. A bank question meets it by a person checking it; a generated one meets it by construction, and `maths_generator_test.dart` proves it by **re-parsing each question's text** and recomputing the answer independently of the generator, over every single-operation and single-table setting and hundreds of seeds. The test does not trust the generator's own arithmetic. |
| No wrong answer is also right | The same rule for distractors: each of the three wrong answers differs from the right one and from each other, and none is negative. Asserted by the same test. |
| Whole numbers only | Subtraction never goes below zero and division is always exact (`a ÷ b` is built as `(b × k) ÷ b`), because negative numbers and remainders are not what a child choosing "taking away" or "dividing" is practising. Asserted by the test. |
| Settings are per profile | Siblings on one tablet know different tables, as they have read different books (`PLAN-phase-10-quiz.md` §4.7). |
| The play screen is reused unchanged | Its text sizes, layout guarantee (`PLAN-quiz-screen.md` §4.4), retries, sounds and semantics were measured and reviewed; a second play screen would need all of it again. A maths question is a `QuizQuestion` with three wrong answers, so it goes through the same `QuizRound` and `QuizQuestionView`. |
| Text fits the existing caps | The longest question is `What is 100 − 99?` (17 characters) and the longest answer three digits, far inside `maxQuestionLength` (80) and `maxAnswerLength` (30). The generator test asserts both caps so a later wording change cannot break the layout guarantee silently. |
| No ambient randomness | `app/test/no_random_test.dart`. Every choice goes through the round's `GameRng`, seeded from the injected clock as the bank rounds are, so a seeded test pins a whole round. |
| The save stays additive | `PLAN.md` §5.2. One optional block inside `quiz` with defaults; `schemaVersion` stays 1 and every earlier save loads unchanged (§4.4). |
| No time pressure, no scary failure | `AGENTS.md`. No timer; a wrong try greys out and the child tries again, exactly as for a bank question. |
| Touch targets | Every toggle is at least `AppTapTargets.primary` (72 dp), the times-table buttons included. |

---

## 2. Non-goals

| Not in this change | Why |
|---|---|
| Maths questions in *Quiz me* mixed rounds | *Quiz me* draws from ticked titles and rotates by series (`PLAN-phase-10-quiz.md` §4.6); a generated topic has no title cursor to rotate. A child who wants maths taps *Maths*. Can be added later as a tick on the shelf if asked for. |
| Typed answers | Spelling is not the issue here, but a number pad is a second input model and a six-year-old types slowly on glass; three options keep one play screen (`PLAN-phase-10-quiz.md` §2). |
| Fractions, decimals, negatives, remainders, money, time, word problems | §1: whole-number arithmetic is the ask. Each is a further generated topic if wanted. |
| Missing-number questions (`7 + ? = 12`) | A good later variation, but a second question shape to word and test. |
| Adaptive difficulty, or tracking which facts a child gets wrong | Would store per-fact history in the save, which §1 keeps to settings and counters. |
| Times tables beyond 12 | 12 × 12 is the end of the UK primary curriculum's multiplication tables. |
| A timer or a "beat your time" mode | `PLAN.md` §1. |
| A Maths card of its own on the Arcade menu | Maths is a quiz topic, reached through the existing Quiz card. |

---

## 3. Approach

**The load-bearing decision: a maths round is an ordinary `QuizRound` of `QuizQuestion`s, built by a
generator instead of `QuizPicker`.** The play screen, the round model's retries and scoring, the
round-end card and the layout test all apply unchanged. What changes is where a round's effect is
written: a maths round has no title cursor, so `QuizRound.applyTo` writes only the maths counters
(§4.3). If this changed — a maths play screen of its own — every guarantee `PLAN-quiz-screen.md`
measured would have to be measured again.

**The second decision: the save stores the settings, not the questions.** Settings are three small
fields per profile; a question is generated fresh each time. So changing the generator later (better
distractors, a new operation) needs no save migration, and nothing a child has done depends on what
the generator produced before.

| Option | Rejected because |
|---|---|
| A JSON pack of sums under `assets/quiz/store/` | The ask says not a bank. It also cannot follow a child's own table choice without a pack per combination, and each of its thousands of entries would need a person's check. |
| Generating questions into the catalog at load as a fake series | Gets *Quiz me* and *Pick one* for free, but the shelf's title cursors would then store a seed over a pool of generated facts that changes with the settings, and a setting toggle would reset every order. Settings belong to the profile, not the catalog. |
| A separate maths game on the Arcade or Puzzles menu | The quiz already has the right screen; the owner asked for maths as a quiz topic. |
| Sampling facts uniformly across all chosen operations | Adding up to 100 has about 5,000 facts and one times table 12, so a mixed setting would be almost all adding. Operations rotate instead (§4.2). |
| Rejection sampling for no-repeat draws | A loop whose length depends on luck, which `PLAN-phase-10-quiz.md` §4.6 rejected for the same job. A partial Fisher–Yates over each operation's fact list draws without repeats in a fixed number of steps. |
| Free-standing distractors (any random number) | Too easy: `7 × 8` against `13` and `91` is not a question. Distractors are near misses (§4.2). |

---

## 4. Design

### 4.1 Settings

```dart
enum QuizMathsOp { add, subtract, multiply, divide }

class QuizMathsProgress {        // in core/storage/save_data.dart, on QuizProgress.maths
  Set<QuizMathsOp> ops;          // default {add, subtract}
  Set<int> tables;               // 1..12, default {2, 5, 10}
  int upTo;                      // 10, 20 or 100, default 10: the size of adding and taking away
  int rounds;                    // finished maths rounds
  int best;                      // best score, 0..10
}
```

- `upTo` bounds adding (the sum) and taking away (the starting number). It is offered only as 10, 20
  or 100: the steps a primary school takes, and few enough for one row of buttons.
- `tables` drives both times tables and dividing: a child who knows the 5 times table is asked
  `5 × 7` or `7 × 5` and `35 ÷ 5`.
- A setting is **playable** when at least one operation is on and, if times tables or dividing is on,
  at least one table is chosen. *Start* is disabled with a one-line hint otherwise, as *Quiz me* is
  with nothing ticked (`PLAN-phase-10-quiz.md` §4.5).
- Defaults are a starting point for a child of about six: adding and taking away within 10, and the
  2, 5 and 10 tables, which are taught first. They are constants, and §9 keeps them open.

### 4.2 The generator

`model/maths_generator.dart`, pure Dart like the rest of `model/`:

```dart
QuizRound? mathsRound(QuizMathsProgress settings, GameRng rng);  // null if not playable
```

**Facts.** Each chosen operation enumerates its facts, in a fixed order:

| Operation | Facts | Shown as | Count |
|---|---|---|---|
| add | `a + b`, `a, b ≥ 1`, `a + b ≤ upTo` | `What is a + b?` | 45 / 190 / 4,950 |
| subtract | `a − b`, `1 ≤ b ≤ a ≤ upTo` | `What is a − b?` | 55 / 210 / 5,050 |
| multiply | unordered pairs `{t, k}`, `k` in 1..12, `t` a chosen table | `t × k` or `k × t`, coin toss | at least 12 |
| divide | `(t × k) ÷ t`, `k` in 1..12, `t` a chosen table | `What is n ÷ t?` | 12 per table |

Multiplication facts are unordered so that with the 3 and 4 tables both chosen, `3 × 4` and `4 × 3`
are one fact, and a round cannot ask the same thing twice in two spellings. Every playable setting has
at least 12 facts per operation, more than the 10 a round can draw from one operation, so a round
never repeats a fact; the test pins that by checking the smallest setting of each operation.

**A round.** The chosen operations, in enum order, are shuffled; question *i* takes operation
`i mod n`, so a round over four operations asks each two or three times. Within an operation, facts
are drawn without replacement by a partial Fisher–Yates over its fact list. The rng is consumed in a
fixed order — the operation shuffle, then per question the fact draw and, for multiplication, the
operand order, then distractors — and after that `QuizPicker`'s own option presentation, so a seeded
test pins a round.

**Wrong answers.** Three near misses, distinct, non-negative and not the answer:

- add and subtract: answer ±1 and ±2, and ±10 when `upTo` is 100, plus the other operation's result
  (`a − b` for a sum, `a + b` for a difference) — the commonest slip.
- multiply: the neighbouring products `answer ± t` and `answer ± k`, plus `t + k`.
- divide: the quotient ±1 and ±2, plus the divisor itself.

Candidates are filtered, shuffled, and the first three taken; if fewer than three survive (an answer
of 0 or 1), the next whole numbers above the answer fill in. The round then shows the answer and two
of the three, chosen by the same presentation `QuizPicker` uses, so maths and bank questions look
alike.

**As `QuizQuestion`s.** Each is `checked: true` (§1: correct by construction), `level: 1` (a maths
round keeps its rotation order rather than being re-sorted), `source: 'generated'`, and an id
`maths.<op>.<a>.<b>` that identifies the fact for the no-repeat check and for test failures. The id
shape is outside the bank's `<title>.<nnn>` rule on purpose: these never go through the pack
validator and never reach the save.

### 4.3 The round and its save

`QuizRound` gains a kind: `QuizRound.maths(questions)`, beside the existing title and mixed
constructors. `isMaths` is true and `isMixed` false for it. `QuizRound.applyTo`, for a maths round,
touches only `quiz.maths`: a finished round adds one to `rounds` and raises `best`; a quit writes
nothing, since there is no order to advance. Title cursors, `mixed` and `known` are never touched.
`QuizRoundQuestion`'s cursor fields are zero for a maths question and are never read, because
`applyTo` branches on the kind before it reads them.

### 4.4 Save field

```json
"quiz": {
  "known": [...], "titles": {...}, "mixed": {...},
  "maths": { "ops": ["add", "multiply"], "tables": [2, 3, 5, 10], "upTo": 20, "rounds": 4, "best": 9 }
}
```

- Every key optional. A save without `maths` decodes to the defaults, so `preMathsSaveJson`, the
  encoder's output for `fullSave()` before this change, decodes with only `quiz.maths` defaulted.
- `ops` written in enum order and `tables` sorted, so the file does not churn with set order.
- Leniency follows the quiz block's rule (`save_codec.dart`, `_readQuiz`): a wrong *type* is a format
  error naming its path; a value of the right type that makes no sense is dropped. An unknown op name
  (from a later build) or a table outside 1..12 is dropped; an `upTo` other than 10, 20 or 100 reads
  as 10; a negative `rounds` or `best` reads as 0. A setting is not progress, so dropping an unknown
  value costs a child one toggle.
- `schemaVersion` stays 1. `QuizProgress` is nested inside `Profile`, so a players file carries
  `maths` through `transfer_codec.dart` unchanged and `ProfileImportEntry.result`, which copies
  `quiz` whole, needs no change.

### 4.5 Screens and navigation

```
Arcade ─ Quiz ─┬─ Quiz me ─► Play
               ├─ Pick one ─► Play
               ├─ My shelf
               └─ Maths ─► Play       (new: /quiz/maths, then /quiz/play with QuizPlayArgs.maths())
```

- **The Quiz menu** gains a fourth `BigButton`, *Maths*. The three bank buttons appear only when the
  catalog offers a title: today's store release build offers none (every store question is
  unchecked), so its Quiz menu is *Maths* alone rather than two dead ends and an empty shelf.
- **The Quiz card on the Arcade menu always appears.** It was hidden over an empty catalog because a
  card that opens an empty quiz is a dead end (`PLAN-phase-10-quiz.md` §4.5); Maths is never empty,
  so that reason is gone. This supersedes §4.5's rule, and the store build gains its first quiz. The
  card's best line is the better of the mixed and maths bests, *Not played yet* until either is
  played.
- **The Maths screen** (`/quiz/maths`), top to bottom: *Start* (disabled with a hint when not
  playable), the best maths score once played, then *What to practise* — four toggles with the
  operation's symbol (`+`, `−`, `×`, `÷`) and a word (*Adding*, *Taking away*, *Times tables*,
  *Dividing*) — then *Numbers up to* (10, 20, 100), shown only when adding or taking away is on, and
  *Times tables I know*, twelve square toggles 1–12, shown only when times tables or dividing is on.
  *Start* is first so a returning child, whose settings are remembered, starts in one tap.
- Every toggle writes through `ProgressRepository.updateQuizMaths` with the store's usual debounce,
  as a shelf tick does. Toggling the last operation off is allowed — *Start* then explains — because a
  toggle that refuses to turn off is more confusing than a disabled button with a reason.
- `BigButton` gains a `BigButton.glyph` constructor drawing a text symbol where the icon goes,
  because Material Icons has no division sign and the operation buttons should show the symbol the
  child will see in the question.
- **Play again** on the round-end card starts a fresh maths round with the current settings.

---

## 5. Repository layout

```
app/lib/core/storage/save_data.dart        # QuizMathsOp, QuizMathsProgress, QuizProgress.maths
app/lib/core/storage/save_codec.dart       # read and write quiz.maths
app/lib/core/storage/progress_repository.dart  # updateQuizMaths
app/lib/core/ui/big_button.dart            # BigButton.glyph
app/lib/features/quiz/model/
  maths_generator.dart                     # facts, distractors, mathsRound — no Flutter
  quiz_round.dart                          # QuizRound.maths, applyTo's maths branch
app/lib/features/quiz/ui/
  quiz_maths_screen.dart                   # /quiz/maths
  quiz_menu_screen.dart, quiz_play_screen.dart, quiz_style.dart
app/lib/features/arcade/arcade_menu_screen.dart  # card always shown, combined best
app/test/features/quiz/maths_generator_test.dart
app/test/features/quiz/ui/quiz_maths_screen_test.dart
```

The generator sits in `model/` beside `QuizPicker` because it is the same job — build a round — and
imports nothing from Flutter, so its exhaustive test runs in plain `test()`.

---

## 6. Phases

One pull request in three commits, by one agent session working full time; about one day, most of it
the tests. The range is narrow because the play screen is reused.

**Phase 1 — settings, save field and generator.** `QuizMathsOp`, `QuizMathsProgress`, the codec,
`maths_generator.dart`, `QuizRound.maths` and its `applyTo` branch, with their tests.
**Done when:** `maths_generator_test.dart` re-parses every question of 400 seeded rounds per
single-operation setting, every single-table setting and a mixed setting, and finds the answer right,
three distinct non-negative wrong answers, no repeated fact in a round, only the chosen operations and
tables, and text within the caps; an unplayable setting returns null; a seeded round is identical
twice; `preMathsSaveJson` decodes with `maths` defaulted and nothing else changed; a profile with
maths settings round-trips through the save codec and a players file; an unknown op and table 13 are
dropped; `schemaVersion` is still 1.

**Phase 2 — screens.** The Maths screen and route, the menu's fourth button, the play screen's maths
kind, `BigButton.glyph`, and the always-shown Quiz card.
**Done when:** a widget test toggles operations and tables on the Maths screen and sees them in the
save; *Start* is disabled with the hint when times tables is on with no table chosen; a widget test
plays a maths round to the round-end card and sees `quiz.maths` rounds 1 and best written, with
`mixed` and `titles` unchanged; the Quiz menu over an empty catalog shows only *Maths*; the Arcade
menu shows the Quiz card over an empty catalog; `layout_sweep_test.dart` passes with `/quiz/maths`.

**Phase 3 — documents.** This file closed with an outcome; `PLAN-phase-10-quiz.md` §4.5 marked
superseded where the card and menu rules changed; `PLAN.md` §7's phase 10 entry names Maths.
**Done when:** `tool/verify.sh` passes and the three documents agree with the code.

---

## 7. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| A generated "right answer" is wrong | High | The test recomputes every answer from the question text with its own parser, never the generator's numbers, over every single-operation and single-table setting at 400 seeds each. |
| A wrong answer is also right, or negative | Medium | Asserted by the same test for every generated question. |
| A setting with too few facts repeats a question in a round | Medium | Every playable setting has at least 12 facts per operation (§4.2) and draws are without replacement; the test checks the smallest setting of each operation. |
| The store build's Quiz menu shows bank buttons that lead nowhere | Medium | The bank buttons appear only when the catalog offers a title; a widget test over the empty catalog asserts only *Maths* shows. |
| Always showing the Quiz card changes Arcade menu tests that counted cards | Low | Those tests are updated in the same change; the Invaders and Snake behaviour they test does not change. |
| Unicode `−`, `×`, `÷` read badly by a screen reader | Low | TalkBack and VoiceOver read U+2212, U+00D7 and U+00F7 as minus, times and divided by. Checked on a device in §8; if not, the question gets a semantics label in words. |
| A child finds the defaults too hard or too easy | Low | Settings are remembered per profile and changed in one tap; defaults are constants (§9). |

---

## 8. Verification checklist

- [x] `cd app && flutter test test/features/quiz/maths_generator_test.dart` passes; breaking the
      subtraction bound, the division construction, the distractor filter or the multiplication
      itself each fails it.
- [x] `cd app && flutter test test/core/storage` passes, including the `preMathsSaveJson` decode.
- [x] `cd app && flutter test test/features/quiz test/features/arcade test/layout_sweep_test.dart`
      passes.
- [x] `tool/verify.sh` passes.
- [ ] *(Device)* A six-year-old sets up adding within 10, plays a round unaided after one
      demonstration, and an adult sets their known tables in under a minute.
- [ ] *(Device)* TalkBack reads `What is 7 × 8?` as "what is 7 times 8".

---

## 9. Open questions

| Question | What resolves it |
|---|---|
| The defaults: adding and taking away within 10, tables 2, 5 and 10. | The owner, after watching a child use it. Constants in `save_data.dart`. |
| Should Maths join *Quiz me* as a tickable topic? | The owner (§2). |
| Missing-number questions, number bonds, doubling and halving. | The owner; each is a further fact shape in the generator. |
| Should the times-table screen offer *All* and *None* shortcuts? | The device pass: whether twelve taps is a chore. |

---

## 10. Starting order

1. Freeze `encodeSave(fullSave())` as `preMathsSaveJson` before touching the save, so the fixture
   is the old encoder's real output.
2. The generator and its re-parsing test, before any screen can show a question.
3. The save field, then the screens.

---

## 11. Outcome

Built as planned, in one pull request. Differences and findings:

- **A latent bug in `QuizRound.applyTo`.** It rebuilt `QuizProgress` field by field, so once
  `maths` existed any bank round's save would have reset the Maths settings to the defaults. It now
  copies the current progress and replaces only `titles` and `mixed`. `quiz_round_test.dart` has a
  test that fails against the old construction.
- **Option presentation is shared.** `QuizPicker`'s private `_present` became the top-level
  `presentOptions`, and `_shuffle` became `quizShuffle`, so a Maths round shows its answer and two of
  three wrong answers exactly as a bank round does. The rng is consumed in the same order, so every
  seeded bank test passed unchanged.
- **Settings are written by `ProgressRepository.updateQuizMaths`**, a one-line wrapper over
  `updateQuiz`, rather than a setter per field.
- **The glyph is drawn at the icon's size, unscaled by text size**, as an icon is, and excluded from
  semantics: the label beside it says the same in words.
- **The times-table and size toggles are a local `_NumberToggle`**, not `BigButton`: a 72 dp square
  has no room for `BigButton`'s padding. It draws selection the same way — container colour, a 3 dp
  border and a check — so selection never rests on colour.
- **Tests changed because the Quiz card always shows**: three Arcade menu tests count one more
  *Not played yet*, and `store_bank_test.dart` now asserts the release filter on the Quiz menu
  (only *Maths* over the unchecked store, the bank's buttons once ten are checked) rather than on the
  card's presence.
- **Layout.** `layout_sweep_test.dart` covers `/quiz/maths` at the fresh save's defaults, which
  hide the times-table grid, so `quiz_maths_screen_test.dart` also renders every section at 200 %
  text on 360 x 640 and 640 x 360 dp. Screenshots were taken in a widget test with Roboto loaded,
  not on a device.

