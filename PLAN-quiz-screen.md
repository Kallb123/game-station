# Quiz play screen for young readers

The quiz play screen built in phase 10 PR 6 (`PLAN-phase-10-quiz.md` §4.5, §4.8) draws the question
at body size (18 dp) in regular weight, the answers as plain purple buttons, and the progress as
14 dp dots. It was squeezed that small to fit a 360 x 640 dp window at 200 % text without scrolling,
and the question cap came down from 100 to 60 characters for the same reason. On a real phone or a
Fire tablet the result is a question too small for a six-year-old to read comfortably.

This plan redesigns the play screen from the owner's Claude Design ("Quiz — a screen kids can
actually read", frames 2a–2d and 3a), relaxes the screen-size guarantee the layout is measured
against, and lets the measurement raise the text caps. It is one pull request of three commits.
**The release line is the whole pull request**; the deferred items in §2 and §9 do not block it.

## 1. Scope and constraints

| Constraint | Rationale |
|---|---|
| Question 30 dp bold in its own card, 34 dp when the screen has two columns; answers 24 dp bold; line height 1.3 | The design's sizes. Nearly twice the old 18 dp regular, which is the complaint. |
| Question and answer text grow with the system text setting up to **36 dp** and stop there (`TextScaler.clamp`) | 36 dp is what the old 18 dp text reached at 200 %, so no setting draws the quiz smaller than before. Unclamped, a 30 dp question at 200 % is 60 dp, about five characters a line on a phone, which helps nobody. Android 14's own non-linear font scaling makes the same judgement: it scales 30 sp text about 1.27x at 200 %. |
| Each answer has a colour **and** a shape — circle, triangle, square, by position | Colour never carries meaning alone (`tokens.dart`, `AGENTS.md`); a pre-reader helped by an adult can be told "the triangle one". |
| Colours are `AppTheme.roleScheme(seed).primaryContainer` / `onPrimaryContainer` for the `sudoku`, `arcade` and `draw` seeds | The design's "three home-card colours". The pairing is already held above 7:1 for every role seed in both themes by `contrast_test.dart`, so no new hex values enter the app. |
| A wrong answer greys out with *Not this one* and a cross, and the child tries again; nothing turns red | The design's "gentle wrong answers", and `AGENTS.md`'s "no scary failure states". |
| The score stays *right first go, out of 10*, and the save format does not change | With one try per question the old score was right answers out of ten, which is the same number. Saved bests stay comparable, and no save migration or transfer change is needed. |
| Every answer and the reserved *Next* slot keep their size across idle, try-again and solved states | The design's "nothing jumps": a button must not move under a finger. Enforced by building the feedback slot as an `IndexedStack`, which sizes to its largest child at any text scale. |
| No-scroll guarantee at **100 % text** on **360 x 760 dp** (portrait phone) and **960 x 528 dp** (Fire HD 8 sideways) | 360 x 640 is a 2014 phone including its bars; a current 360 x 800 phone leaves about 760 dp after status and gesture bars, and the Fire HD 8's 960 x 600 dp screen leaves 528 after its status and navigation bars. At 200 % the clamped text cannot fit any phone (§4.4), so 200 % is held to *no overflow* instead. |
| At larger text the page scrolls, with a visible scrollbar, and *Next* is scrolled into view when it appears | §4.8's objection to scrolling was an answer below the fold that a child does not know exists. A permanently visible thumb says there is more; scrolling *Next* in removes the one dead end. |
| Caps are measured, not chosen: the question cap rises in steps of 5 as far as the guarantee windows allow, never below **60**; the answer cap likewise, never below **30** | The floors are today's caps, so no question in the bank can start failing. The phase 10 PR 6 method (§4.8) is kept: the content test enforces the cap, and `quiz_play_layout_test.dart` renders every real question. |

## 2. Non-goals

- **No Listen button.** The design reads the question aloud through `flutter_tts`. That is a native
  plugin on six platforms — it has no Linux implementation, needs a `<queries>` entry on Android 11+,
  and must pass `tool/check_offline.dart` — and phase 10 §1 chose screen-reader semantics precisely
  to avoid a new dependency. It is its own change, once the owner decides (§9).
- **No Andika typeface.** Bundling a font is an asset, a licence file and a re-measurement of every
  cap. The app keeps Roboto; the design's sizes and weights are taken without the face (§9).
- **No round-end redesign.** The design's finished frame (2d) shows a star per first-go answer.
  `CompletionCard.score` is shared with nothing else yet, but redrawing it is separate from making the
  question readable; *7 out of 10* with one to three stars stays.
- **No change to the menus, the shelf, the picker or the save.**

## 3. Approach

Rebuild `QuizQuestionView` and its private widgets in place, change `QuizRound` to allow retries,
and re-measure with the existing layout test rewritten for the new guarantee windows.

| Alternative | Rejected because |
|---|---|
| Keep the one-try model and only restyle (wrong answer locks and reveals the right one) | The design's main behavioural change. A child shown "wrong" plus the answer learns less than one who finds it, and the reveal needs a "wrong" colour the design removes. |
| Keep the 360 x 640 at 200 % guarantee and fit bigger text by lowering the caps | At 36 dp a 360 dp phone holds about 15 characters of question a line; the caps would fall below the bank's existing questions, which is the opposite of the ask. |
| No text clamp; let 200 % scale the 30 dp question to 60 dp | Five characters a line and a page several screens tall. The clamp still gives every setting at least the old size. |
| Hard-code the design's hex colours (`#86D5C3`, `#DFB7F4`, `#FFB68A`) | They are tuned for the night theme only. The role containers they were taken from exist for both themes and are already contrast-tested. |
| Shrink the answer font on narrow phones to fit 360 x 640 | Recreates the complaint on the smallest phones, which are the ones young children are handed. |

**The load-bearing decision is the guarantee: 100 % text on 360 x 760 and 960 x 528, with the 36 dp
ceiling.** The caps are whatever fits it. Moving either window, the ceiling or the type sizes means
re-running the measurement, and if the caps would then fall, content has to be rewritten — which is
why the floors are today's 60/30.

## 4. Design

### 4.1 `QuizRound` with retries

```dart
bool answer(int option);   // right: solves the current question; wrong: records the try.
                           // Throws if the question is solved or [option] was already tried.
bool isSolved(int i);
List<int> wrongTriesAt(int i);   // unmodifiable, in tap order
void advance();            // needs the current question solved
int get solvedCount;       // replaces answeredCount
int get score;             // solved with no wrong try
bool get isComplete;       // every question solved
```

`chosenAt` goes. `applyTo` advances a title's cursor over **solved** questions only: a question
quit after wrong tries was not answered and is asked again next time. The quit dialog appears when
`solvedCount > 0`, as it does for `answeredCount` today. With three options a question is solved by
the third tap at the latest.

### 4.2 Screen parts (`quiz_play_screen.dart`)

Top to bottom on a phone:

1. **Top row**, 56 dp: a round 56 dp back button (`surfaceContainerHigh` fill), a ten-segment
   progress bar (14 dp high, radius 7, gap 6: solved segments `primary`, the current one ringed in
   `primary` over `primaryContainer`, the rest `surfaceContainerHighest`), and a `3 / 10` counter.
   One `Semantics` label, *Question 3 of 10*, as the dots had.
2. **Question card**, radius 28, the arcade scheme's `surfaceContainerHigh` with `onSurface` text,
   padding 24/22: a tinted surface rather than a container colour, so the card cannot be mistaken for
   the second answer, which is the arcade container. A `Semantics(header: true)` text. The debug-only
   *unchecked* chip stays above it.
3. **Three answers**, gap 12. Each a `Material` + `InkWell` (kept from PR 6: a disabled button would
   turn grey and lose the state colours), radius 28, at least 88 dp tall, padding 12/16/12/22: the
   shape (26 dp, `StarBorder.polygon(sides: 3)` for the triangle), the label, and a 44 dp badge when
   it has one. States:

   | State | Look | Semantics |
   |---|---|---|
   | open | role container fill, role ink | `label`, button, enabled |
   | tried wrong | `surfaceContainerHighest` fill, `onSurfaceVariant` ink, grey shape, cross badge, *Not this one* under the label | `label, not this one`, disabled |
   | right (solved) | role fill, 4 dp `onSurface` ring outside a 4 dp gap, tick badge | `label, right answer`, disabled |
   | other (solved) | open look at 40 % opacity | `label`, disabled |

4. **Feedback slot**, an `IndexedStack` of three: *Tap an answer* (idle); a smiley and *Good try!
   Have another go.* in a rounded `surfaceContainerHigh` box (after a wrong try); a star and *Yes!
   Well done!* above the *Next*/*Finish* `BigButton` (solved). Only the visible child is in the
   semantics tree and hit-testable; the stack's height is the tallest child's, so nothing above it
   moves.

**Two columns** when the space the view is given is at least 720 dp wide and wider than it is tall
(the Fire tablet sideways): the question card fills the left column; answers and the feedback slot
the right. `ContentWidthCap` applies only to the one-column layout, since two columns need the width.

Sizes, radii and the 36 dp ceiling go in `tokens.dart` as a quiz group, because that file is where
every size lives (`tokens.dart` header). Words go in `quiz_style.dart` beside the existing labels.
Sounds and haptics are unchanged: `sudokuCorrect` and `tap()` on a right answer, `sudokuWrong` at half
gain on a wrong one.

### 4.3 Scrolling

The body stays a `SingleChildScrollView` inside a `LayoutBuilder` with `minHeight` of the viewport,
wrapped in a `Scrollbar(thumbVisibility: true)` so a page that scrolls says so. When a question
becomes solved, the screen calls `Scrollable.ensureVisible` on the feedback slot, so *Next* is on
screen without the child having to find it.

### 4.4 Measurement (`quiz_play_layout_test.dart`)

Kept: Roboto loaded from the SDK's `material_fonts`, the real route, every question in the bank with
its own three longest answers, and a run at exactly the caps. Changed:

- The state measured is the worst one: **two wrong tries, then the right answer** — two *Not this
  one* lines and a tick badge at once.
- **No-scroll** at 100 % on 360 x 760 and on 960 x 528: no exception, `maxScrollExtent == 0`, every
  answer and *Next* wholly inside the window.
- **No overflow** at 200 % on 360 x 640 (the old window, now the worst case rather than the target):
  no exception, and after the scroll-into-view *Next* is wholly inside the window.
- The caps run prints where *Next* ends in each window, for the plan's outcome.

The estimate behind the windows, at Roboto Bold's roughly 0.53 em average advance: a 60-character
question takes four lines of 30 dp in the phone card's 288 dp, and the worst answer state about
320 dp, for roughly 760 dp in all. That is why 360 x 760 is the phone window and why the question
cap may not rise on phones; the test decides.

## 5. Repository layout

| File | Change |
|---|---|
| `app/lib/features/quiz/model/quiz_round.dart` | §4.1. |
| `app/test/features/quiz/quiz_round_test.dart` | Retry, score and `applyTo` cases. |
| `app/lib/core/ui/tokens.dart` | Quiz size group and the 36 dp ceiling. |
| `app/lib/features/quiz/ui/quiz_style.dart` | New words. |
| `app/lib/features/quiz/ui/quiz_play_screen.dart` | §4.2, §4.3. |
| `app/test/features/quiz/ui/quiz_play_screen_test.dart` | Try-again flow and the new semantics labels replace the error-colour assertions. |
| `app/test/features/quiz/ui/quiz_play_layout_test.dart` | §4.4. |
| `app/lib/features/quiz/model/quiz_catalog.dart` | `maxQuestionLength` / `maxAnswerLength` to the measured values. |
| `PLAN-phase-10-quiz.md` | §1 caps row, §4.3, §4.5 *Play*, §4.8 and §8 point here for what superseded them. |

Nothing moves out of `features/quiz/`; the model stays pure Dart.

## 6. Phases

Estimates assume one agent session per phase with review, as phase 10's were.

**Phase 1 — retries in the model.** §4.1 and its tests; the play screen is adjusted only as far as
it needs to compile and its existing tests to pass. *About an hour.*
**Done when:** `quiz_round_test.dart` asserts that a wrong answer can be followed by another,
that a repeated wrong option and an answer after solving throw, that `score` counts only first-go
answers, and that `applyTo` after a quit with wrong tries on the current question leaves that
title's cursor where the last solved question put it; `flutter test test/features/quiz` passes.

**Phase 2 — the screen.** §4.2 and §4.3, the tokens and words, and the play-screen tests. *Half a
day to a day; wide because the two-column layout and the reserved slot are new.*
**Done when:** a widget test taps a wrong answer and sees *Not this one* and the semantics label
`<answer>, not this one`, with no `errorContainer` anywhere on the screen; taps the right one and sees
`<answer>, right answer` and *Next*; the answers' rects are identical before and after each tap; a
960 x 600 window draws the question and the answers side by side; `layout_sweep_test.dart` passes.

**Phase 3 — measure and set the caps.** §4.4; the caps raised as far as both windows allow;
`PLAN-phase-10-quiz.md` reconciled and this plan's outcome written. *Two to three hours.*
**Done when:** `quiz_play_layout_test.dart` passes for every bank question in both windows and at
200 % on 360 x 640; the content test enforces the new caps; the measured numbers are in §10;
`tool/verify.sh` passes.

## 7. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| 60 characters does not fit 360 x 760 at 100 % in the worst state | Medium | Trim chrome before type, in this order: gaps 16 → 12, card padding 24 → 16, the idle hint's height. The phone type sizes do not go down. If it still fails, the phone window stays as measured and the gap is reported in the pull request rather than hidden. |
| A child at 200 % text never scrolls to the third answer | Medium | Visible scrollbar thumb; the 36 dp ceiling keeps the page about two screens at most. Checked only on a device (§8). |
| Faded answers at 40 % fall below contrast | Low | They are no longer actionable and the right answer carries the ring, tick and label; the semantics still read every answer. Accepted, not mitigated. |
| A saved best from the one-try model reads differently | Low | Same number by construction (§1); `applyTo`'s best comparison is unchanged and tested. |

## 8. Verification checklist

- [ ] `tool/verify.sh` passes.
- [ ] `quiz_play_layout_test.dart` prints *Next*'s bottom edge for the caps in both windows; the
      numbers are copied into §10.
- [ ] Screenshots of the four states (idle, try again, solved, two columns), day and night, taken in a
      widget test with Roboto loaded, attached to the pull request and not committed.
- [ ] *(Device)* On a Fire HD 8 sideways and a 360 dp phone at 100 % text, a round plays with no
      scrolling; at 200 % the scrollbar shows and *Next* scrolls into view. Not answerable in CI.

## 9. Open questions

- **Listen button.** Add `flutter_tts` for the question and answers? Resolved by the owner deciding
  the dependency is worth six platforms' plugin and an offline audit; Linux would need a fallback.
- **Andika.** Bundle it (OFL 1.1) for the question and answers? Resolved by a comparison on the
  owner's device; the caps are then re-measured.
- **Round end.** Show a star per first-go answer, as the design's 2d does?
- **The phone window.** Is 360 x 760 the smallest phone the quiz must fit without scrolling? Resolved
  by the owner's devices; changing it re-runs §4.4.

## 10. Starting order

1. Phase 1: change `QuizRound` and its tests.
2. Phase 2: rebuild `QuizQuestionView` against the new model.
3. Phase 3: rewrite the layout test, raise the caps, reconcile `PLAN-phase-10-quiz.md`.

*Outcome:* to be written in phase 3.
