# Phase 10 — Quiz, trivia about children's books, TV and films

This file is the design and the pull-request breakdown for a fifth game: a multiple-choice quiz about
the stories a child knows. A child ticks the books they have read and the shows and films they have
watched on a shelf, then either plays a mixed round drawn from everything ticked or picks one title
and is quizzed on that alone. Books come first — Enid Blyton's Magic Faraway Tree, Roald Dahl,
Rainbow Magic, Narnia and the Kitty series — then CBeebies (Bluey, Topsy and Tim, Hey Duggee, Witch
Detectives, Waffle the Wonder Dog) and Disney (Mickey, Frozen, the Princess films).

**Two builds, two audiences.** Every pack is either *store* or *private*, decided by which directory
it sits in. A store build — any build not made with the private flavour — carries only store packs; a private
build, made with `flutter build apk --flavor private`, carries both. So the named series can be
played at home without being shipped to a store, while general questions on public-domain stories
go to both (§4.9).

[`PLAN.md`](PLAN.md) is the source of truth for the project; §7 there carries a one-paragraph entry
for this phase pointing here. Where this file and `PLAN.md` disagree, the reason is stated here and
the closing pull request reconciles `PLAN.md`. Read [`PLAN-phase-9-tracks.md`](PLAN-phase-9-tracks.md)
§4.11 and §4.14 first: this phase adds save fields the way Tracks did and sits on the Puzzles menu
Tracks created.

**Named `PLAN-phase-10-quiz.md`, at the repository root**, beside the other phase plans, because code
comments cite these files by path (`AGENTS.md`).

**Release line unchanged:** `PLAN.md` §7 ships at phase 6. Nothing here blocks or advances it. Phase 10
is a minor release after it, as phases 7, 8 and 9 are, and it ships at PR 13 whatever content is
checked by then (§6).

**Contents:**
[1 Scope and constraints](#1-scope-and-constraints) ·
[2 Non-goals](#2-non-goals) ·
[3 Approach](#3-approach) ·
[4 Design](#4-design) ·
[5 Repository layout](#5-repository-layout) ·
[**6 Pull requests →**](#6-pull-requests) ·
[7 Risks](#7-risks) ·
[8 Verification checklist](#8-verification-checklist) ·
[9 Open questions](#9-open-questions) ·
[10 Starting order](#10-starting-order)

---

## 1. Scope and constraints

**The game.** A round is ten questions, one per screen. Each question shows a short sentence and three
large answer buttons, one of them right. Tapping an answer shows at once whether it was right and, if
not, which one was; a **Next** button moves on. The round ends on a card that says how many were
right. There is no timer and no way to lose.

**The three ways in.** From the Quiz menu:

- **Quiz me** — a mixed round from every title the child has ticked on the shelf.
- **Pick one** — a round about a single title, chosen from a list of every offered title, ticked or
  not.
- **My shelf** — every offered title, grouped by series, each with a tick the child toggles: *read*
  for a book, *watched* for a show or film.

| Constraint | Rationale and mechanism |
|---|---|
| A question reaches a child only once a person has checked it against the source | Children trust a quiz. A wrong "right answer" teaches a false fact about a book the child has read and contradicts their own memory of it. Questions are drafted faster than they are checked, and drafts — especially machine-drafted ones — contain confident errors. Every question carries `checked`, set only in a commit by someone who has verified it; release builds load only checked questions (§4.2). The mechanism is the filter in the loader and its test, not the reviewer's diligence. |
| A title is offered only when it has at least ten checked questions | Ten is one round. Below that, a single-title round would repeat questions inside one round, and a mixed round could not draw a fresh question from it. The threshold is one constant, `minQuestionsPerTitle`, and a test asserts that `offeredTitles` never returns a title below it. A title still being checked is hidden, not broken. |
| Text only: no cover art, character pictures, logos, stills or theme tunes | Every series named in the ask is someone else's copyright and trademark. Factual questions written in this repository's own words, naming a title as a title, are the narrowest use; a picture of Elsa or a clip of a theme tune is not. Series are drawn with a Material icon and a colour. `app/assets/quiz/` holds JSON only, and the content test (§4.3) fails on any non-`.json` file in it. |
| Private packs never ship in a store build | The named series are someone else's trademarks, and the owner wants some of them for home use only. A private pack is left out of the store build's asset bundle, not hidden at runtime, so it is not in the binary a store or anyone unzipping it receives. CI unzips the store APK and fails on any `assets/quiz/private/` entry (§4.9). |
| No quotation longer than a short phrase | Same reason. A question may name a character, place or object; it may not reproduce a sentence of the book or a line of a script. The content test refuses a question or answer over its length cap (below), which bounds the damage mechanically; whether a short phrase is a quotation is the reviewer's check. |
| Minimal reading, as far as a quiz allows | `AGENTS.md` asks for minimal reading, and a quiz is reading. This is the one game in the app built for readers, roughly six and over, or a grown-up reading aloud. It reads as little as it can: three options, not four; a question of at most 100 characters and an answer of at most 30, enforced by the content test; and every question and answer exposed as semantics, so TalkBack and VoiceOver read them aloud with no new dependency. The caps are provisional until PR 6 measures them at 200 % text (§4.8). |
| No time pressure, no scary failure | `PLAN.md` §1 and `AGENTS.md`. No timer, no lives, no streak to break. A wrong answer is shown gently — the right answer is highlighted and the child taps Next when ready — and every finished round ends on the same celebration, whatever the score. |
| A question never spoils a title the child has not ticked | Narnia, Faraway Tree and Rainbow Magic are series, and a question about book four answered on the strength of book one gives book four away. Every question belongs to exactly one title — the earliest a reader would need to answer it — and a mixed round draws only from ticked titles (§4.1, §4.6). |
| No network, no new package | `PLAN.md` §1. Questions are bundled assets parsed with `dart:convert`. `app/pubspec.yaml` gains one asset directory and no dependency, so `tool/check_offline.dart` has no new graph to audit. `check_offline.dart` scans `app/lib` for URLs and not `assets/`, so the content test refuses `://` in any question, answer or source itself (§4.3). |
| No ambient randomness | `app/test/no_random_test.dart`. Question order and answer order come from `GameRng`, moved from `features/arcade/shared/` to `core/` unchanged (§4.6). |
| The save stays additive | `PLAN.md` §5.2. One optional profile field with an empty default; `schemaVersion` stays 1 and an old save loads unchanged (§4.7). |
| Touch targets | Answer buttons, Next, the shelf's ticks and every menu card are at least `AppTapTargets.primary`. No exception is needed: a quiz has no grid. |
| `tool/verify.sh` green before every commit | `AGENTS.md`. The content test reads every pack on every run; PR 2 records its cost in §8. |

---

## 2. Non-goals

| Not in this phase | Why |
|---|---|
| Picture, sound or video questions | §1: the pictures and sounds that would make them worth having are someone else's. |
| Free-text answers | Spelling becomes the test instead of the story, and a six-year-old types slowly on glass. |
| True/false questions | A coin toss scores half; three options make a guess the worse strategy. A later content addition if wanted, since a true/false question is a two-option question. |
| A timer, a score leaderboard, or questions against the clock | `PLAN.md` §1. |
| Two players taking turns on one tablet | A second mode with its own screens. §9 keeps it open. |
| Built-in read-aloud (`flutter_tts` or similar) | A dependency to audit, and Android's speech engine is a separate app whose voices may be fetched online, which this app cannot vouch for. The platform screen reader already reads every question (§1). §9 keeps it open. |
| Resuming a round after a force-quit | A round is ten questions and about two minutes. Persisting one means an in-progress record, a codec and a resume path for a loss of at most nine answers. Progress is written at the end of each round (§4.7). |
| Questions written or edited by a parent in the app | An editor, a validation UI and a second content source. The content format is plain JSON, so a parent who wants their own pack can have one added as a file. |
| New questions downloaded after install | No network, ever (`PLAN.md` §1). New questions arrive with an app update. |
| One tick per Rainbow Magic book | Rainbow Magic has more than two hundred books in sets, mostly of seven. A tick per book is a shelf of hundreds and a content job of thousands of questions. The set is the title (§4.1); §9 keeps per-book ticks open. |
| One tick per TV episode | The same arithmetic for Bluey and Hey Duggee. A show is one title. |
| Every Roald Dahl book, every Rainbow Magic set, every Disney film | §4.4 names the launch list. More titles are content-only pull requests later, needing no code. |
| Adaptive difficulty or a per-profile age setting | Questions are tagged with a level now, because tagging nine hundred later is the expensive part, and a round orders easier questions first (§4.6). A per-profile *harder questions* switch is §9's. |
| Naming any series in the store listing | Trademark rules on Amazon and Apple apply to listing metadata. §7 and §9. |
| A private build on iOS, Linux or Windows | `flutter build linux` and `flutter build windows` take no `--flavor` in Flutter 3.44, and iOS flavours need per-flavour Xcode schemes and build configurations for a platform the owner does not install from source. Those builds are always store builds (§4.9). macOS could take one later; nothing in the design prevents it. |
| Marking single questions private inside a store pack | The audience is a file's directory because a file is the unit a build can leave out. A question-level flag could only be filtered at runtime, leaving the text in the store binary. A series that needs both splits into two packs. |

---

## 3. Approach

Build the plumbing first against a small real pack, then fill it with content one group at a time,
books before screens: the order the ask gives.

1. **The content format, the loader and the content test**, with the four Faraway Tree books as the
   first pack, before anything can display a question.
2. **The save field**, before anything can write it.
3. **The round model** — question selection, option order, scoring — as plain Dart.
4. **The screens** — the Quiz menu, the shelf, the title list, the play screen and the end of round —
   and the Quiz card on the Puzzles menu.
5. **Content**, one pull request per group: Narnia; Roald Dahl; Rainbow Magic and Kitty; CBeebies;
   Disney.
6. **The device pass and the close.**

**The load-bearing decision: questions are data, keyed by stable title ids, and the save stores only
title ids and counters — never a question.** A pack is a JSON file under `app/assets/quiz/`; a
profile stores which title ids are ticked and, per title, where it is in that title's question order.
Questions can then be added, corrected, checked or withdrawn in any release without a save migration,
because no save names one. What breaks if this changes: storing question ids (to remember which were
asked, say) makes every correction or withdrawal a dangling reference in some child's save, and
grows a file that `PLAN.md` §5.2 holds to a few kilobytes by a few kilobytes per title. What it costs:
**title ids are frozen once shipped**, exactly as puzzle ids are — renaming `dahl.bfg` would untick
it on every shelf. The content test makes an id's shape strict, and §4.1 says how a title is retired
rather than renamed.

**The second decision: a question is offered only once checked, and a title only once ten of its
questions are.** Content is where this phase's work and risk both concentrate (§7), and an unchecked
fact must not be able to reach a child by an oversight in review. Making the gate a filter in the
loader means a pack can be merged half-checked, played in a debug build, and checked over time, while
a release build shows only what is ready.

Alternatives considered:

| Option | Rejected because |
|---|---|
| Questions as Dart `const` tables, as the sprites are | Type-checked and needing no parse, but nine hundred multi-line literals are what `dart format` reflows on every edit, so a one-word correction becomes a noisy diff. Content would also be reviewable only by someone reading Dart. The parse failure JSON allows is covered instead by the content test in CI and a loader that skips a bad pack (§4.2). |
| YAML packs (`package:yaml`) | Kinder to hand-edit, but a dependency to add and audit for a format JSON already covers. |
| `drift` or SQLite for the questions | A database for under a megabyte of read-only text that is read once at startup. |
| Generating questions on the device with a language model | No network (`PLAN.md` §1), a model too large to bundle, and an unchecked fact on every screen — the opposite of §1's first constraint. |
| Remembering every asked question id in the save | §3's load-bearing decision; replaced by a per-title shuffled order and a position in it (§4.6), two integers per title. |
| A fourth card on the home screen | The owner chose a Puzzles menu in phase 9 to keep the home screen at three cards, because a fourth forces the landscape row into a 2 x 2 grid (`PLAN-phase-9-tracks.md` §3). The quiz is a third card there instead, one tap further from home. §9 asks the owner to confirm, since a quiz is not a puzzle. |
| Four answer options | More reading per question for no gain at this age; three already makes guessing the worse strategy. |
| A tick per Rainbow Magic book or per TV episode | §2. |
| Separate quiz modes for books, TV and films | One shelf with three groups does it, and a mixed round crosses them freely: a child who has read *Matilda* and watched *Bluey* wants one quiz, not two. The group only changes the word on the tick and the icon. |
| Filtering private packs at runtime from a `--dart-define` | One build command and no Gradle change, but the private text is still in the store APK's assets, which is exactly what keeping it out of a store build is for. |
| An `audience` field in each pack, with the build filtering by it | A field and a location that can disagree. The directory is the only thing Flutter's per-flavour asset declaration can act on, so it is the one source of truth; moving a pack between audiences is a `git mv`. |
| Importing private packs on the device from a file, as a players file is imported | Keeps private content out of every binary and out of the repository, on all six platforms. But it is a second feature — a picker, on-device storage, a parent switch and a validator running on the device rather than in CI — and the ask is a build flag. §9 keeps it as the answer if private content must leave the public repository. |
| A `default-flavor: store` entry in `pubspec.yaml` | Would make an unflagged command a store build on every platform, but it applies to iOS and macOS too, where a flavour needs a matching Xcode scheme that does not exist, so CI's `flutter build ios` and `flutter build macos` legs would break. Flavours are declared for Android only, and every other platform builds without one, which excludes private assets anyway (§4.9). |
| Reusing the engine's `Rng` for question order | `PLAN-phase-4.md` §3 rejected exporting the frozen generator for non-frozen uses. `GameRng` exists for this. |

---

## 4. Design

### 4.1 Collections, series and titles

```
collection   book | tv | film            fixed in code; sets the tick's word and the icon
  series     dahl, narnia, cbeebies.bluey …   one JSON file each, in shelf order
    title    dahl.bfg, narnia.silver-chair …  what a child ticks and what a question belongs to
```

- A **title** is the unit a child ticks and picks: one book (*Matilda*), one Rainbow Magic set (*the
  Rainbow Fairies*), one show (*Bluey*), or one film (*Frozen II*). For a show, the series and the
  title are the same thing, and the series file holds one title.
- A **title id** is `<series>.<slug>`, lowercase ASCII letters, digits and hyphens, matching
  `^[a-z0-9-]+\.[a-z0-9-]+$` (CBeebies and Disney series are named `cbeebies-bluey`,
  `disney-frozen`, so the id keeps one dot). Frozen once shipped (§3). A title that must go is
  **withdrawn**, by listing its id in `withdrawnTitles` in the catalog, never by deleting or renaming
  it: a withdrawn title stays ticked in saves and is simply not shown, so restoring it later restores
  every child's tick.
- Titles in a series are in **reading order**, and the series' shelf order is the catalog's. Narnia
  uses the numbering of current editions, with *The Magician's Nephew* first; §9 notes the
  alternative. Order matters for one rule: a question that needs more than one title belongs to the
  latest of them, so it is asked only of a child who has reached it; a question about the series as a
  whole ("Who made Narnia?") belongs to the earliest title that answers it.

### 4.2 Pack format and loading

One file per series under `app/assets/quiz/store/` or `app/assets/quiz/private/` (§4.9), and one
index in each directory listing its packs in shelf order:

```json
// app/assets/quiz/private/index.json
{ "format": 1,
  "series": ["faraway-tree", "narnia", "dahl", "rainbow-magic", "kitty",
             "cbeebies-bluey", "cbeebies-topsy-and-tim", "cbeebies-hey-duggee",
             "cbeebies-witch-detectives", "cbeebies-waffle",
             "disney-mickey", "disney-frozen", "disney-princesses"],
  "withdrawnTitles": [] }
```

The shelf shows store series first, then private ones, each in its index's order.

```json
// app/assets/quiz/private/dahl.json
{ "format": 1,
  "series": "dahl", "name": "Roald Dahl", "collection": "book",
  "titles": [
    { "id": "dahl.matilda", "name": "Matilda",
      "questions": [
        { "id": "dahl.matilda.001", "level": 1, "checked": true,
          "q": "What is the name of Matilda's kind teacher?",
          "a": "Miss Honey",
          "wrong": ["Miss Trunchbull", "Mrs Phelps", "Miss Spider"],
          "source": "Matilda, chapter 'Miss Honey'" } ] } ] }
```

- `a` is the right answer and `wrong` holds **exactly three** wrong ones, of which a round shows two
  chosen at random — so a repeat of a question is not a repeat of its screen.
- `level` is `1` (a child who has had the book read to them could answer) or `2` (needs a close
  read). It orders a round (§4.6) and nothing else in this phase.
- `checked` is set to `true` only by someone who has verified the question, the answer and every
  wrong answer against the source; a wrong answer that is arguably right is as bad as a wrong right
  answer. Drafts land with `false`.
- `source` says where the answer is — a chapter, or an episode or scene — so a checker can find it
  and a later reader can recheck it. Text only; no URL (§1).
- Question ids are `<title id>.<three digits>`, unique across the bank, never reused. They exist for
  review and for the content test, not for the save (§3).

**Loading.** `QuizCatalogLoader` reads `store/index.json`, then `private/index.json` if the build
carries it, and each listed pack through `rootBundle`, once, during app start beside the save, so the
Puzzles menu knows whether to show the Quiz card (§4.5). It parses with `dart:convert` and builds an immutable `QuizCatalog`. A
pack that fails to parse or validate is skipped and logged with `debugPrint`, never shown to a child
(`AGENTS.md`); the content test makes that a CI failure long before a device sees it. Release builds
(`kReleaseMode`) drop every question with `checked: false` at load; debug and profile builds keep
them and mark them with a small *unchecked* chip on the play screen, so the owner can play-test a
draft pack. `offeredTitles` returns the titles with at least `minQuestionsPerTitle` (10) loaded
questions that are not withdrawn.

The whole bank at the launch target (§4.4) is about nine hundred questions, under 300 KB of JSON.
Parsing it is a few tens of milliseconds; PR 2 measures it, and if it exceeds 100 ms on the CI runner
the parse moves to `compute`.

### 4.3 The content test

`app/test/features/quiz/content_test.dart` reads both `app/assets/quiz/store/` and
`app/assets/quiz/private/` with `dart:io`, whatever flavour the test runs under, and fails on:

- a file in either directory that is not in that directory's `index.json`, an index entry with no
  file, a non-`.json` file, or anything in `app/assets/quiz/` outside the two directories;
- a series in both directories;
- a pack that does not parse, a missing or mistyped field, or a `format` other than 1;
- a series id that is not its file name, or a `collection` other than `book`, `tv` or `film`;
- a title or question id that breaks §4.1's or §4.2's shape, does not start with its parent's id, or
  is duplicated anywhere in the bank;
- a question over 100 characters or an answer over 30, or empty text;
- `wrong` not exactly three; any two of the four answers equal after trimming and case-folding;
- an answer of the form "all of the above", "none of the above", "both", or naming an option's
  position — options are shuffled (§4.6), so these become nonsense;
- `://` anywhere in a pack (§1);
- a `withdrawnTitles` entry that names no title in the bank.

Ids are unique across both directories, so a pack moves between them without a title id changing
and a child's ticks survive the move. It prints a coverage table — audience, collection, series,
title, checked and total — so a content pull
request's description can paste it, and asserts nothing about coverage: a half-checked pack is
allowed, and §4.2's threshold is what keeps it from a child. A second test asserts the loader in
release mode drops unchecked questions and hides a title with nine checked. Per `AGENTS.md`, each
rule is run against a deliberately broken fixture under `test/features/quiz/fixtures/` to prove it
fails, not only that the real bank passes.

### 4.4 The launch list

Content targets: **20 questions per title, at least 10 checked to be offered.** The list is the
ask's, with the gaps the ask leaves marked; §9 holds what the owner decides. **Every series in this
table starts private** (§4.9): moving one to the store is a deliberate `git mv` by the owner, never a
default.

| Collection | Series | Titles | Count |
|---|---|---|---|
| Book | The Magic Faraway Tree (Enid Blyton) | *The Enchanted Wood*, *The Magic Faraway Tree*, *The Folk of the Faraway Tree*, *Up the Faraway Tree* | 4 |
| Book | The Chronicles of Narnia (C. S. Lewis) | *The Magician's Nephew*, *The Lion, the Witch and the Wardrobe*, *The Horse and His Boy*, *Prince Caspian*, *The Voyage of the Dawn Treader*, *The Silver Chair*, *The Last Battle* | 7 |
| Book | Roald Dahl | *The Magic Finger*, *James and the Giant Peach*, *Charlie and the Chocolate Factory*, *Fantastic Mr Fox*, *Danny the Champion of the World*, *The Enormous Crocodile*, *The Twits*, *George's Marvellous Medicine*, *The BFG*, *The Witches*, *The Giraffe and the Pelly and Me*, *Matilda*, *Esio Trot* — in publication order; the owner trims | 13 |
| Book | Rainbow Magic | The first sets, one title each: *the Rainbow Fairies*, *the Weather Fairies*, *the Jewel Fairies*. Which further sets is §9's | 3 |
| Book | Kitty | **Unresolved** — which series is meant is §9's first question | — |
| TV | CBeebies | *Bluey*, *Topsy and Tim*, *Hey Duggee*, *Witch Detectives*, *Waffle the Wonder Dog* (the ask's *Waffle the Dog*) — one title each; *Witch Detectives* to be confirmed (§9) | 5 |
| Film | Disney | *Mickey Mouse and friends* (one title; which shows it covers is §9's), *Frozen*, *Frozen II*, and the Princess films — *Snow White and the Seven Dwarfs*, *Cinderella*, *Sleeping Beauty*, *The Little Mermaid*, *Beauty and the Beast*, *Aladdin*, *Pocahontas*, *Mulan*, *The Princess and the Frog*, *Tangled*, *Brave*, *Moana* | 15 |

About 47 titles before Kitty: 940 questions at target and 470 checked to offer them all.

**General packs, for the store.** Stories old enough to be out of copyright carry no one's trademark
in their titles, so they are the natural store content. The proposal, for the owner to trim (§9):

| Collection | Series | Titles | Count |
|---|---|---|---|
| Book | Fairy tales | *Little Red Riding Hood*, *Hansel and Gretel*, *Goldilocks and the Three Bears*, *Jack and the Beanstalk*, *The Three Little Pigs*, *The Gingerbread Man* | 6 |
| Book | Aesop's fables | One title for the collection | 1 |
| Book | Classic stories | *Alice's Adventures in Wonderland*, *The Tale of Peter Rabbit*, *The Wind in the Willows* | 3 |

Ten titles: 200 questions at target, 100 checked to offer them. A fairy tale exists in many versions,
so its questions keep to what the common versions share, and `source` names the version checked
against. Questions are about the original texts, never a film of them. Mickey is a
TV and short-film character rather than one film; it sits under Disney because that is where the ask
put it, as one title.

### 4.5 Screens and navigation

```
Home ─ Puzzles ─┬─ Sudoku
                ├─ Tracks
                └─ Quiz ─┬─ Quiz me ───────────────► Play ─► Round end
                         ├─ Pick one ─ title list ─► Play ─► Round end
                         └─ My shelf
```

- **The Puzzles menu gains a third card, Quiz** (`Icons.quiz`), laid out as its two cards are: a
  column in portrait, a row in landscape. The card appears only when the loaded catalog offers at
  least one title, so a store build made before any store pack is ready has no quiz rather than an
  empty one.
- **The Quiz menu** is three `BigButton`s. *Quiz me* is disabled with a one-line hint — *Tick what
  you've read on your shelf* — when nothing offered is ticked, and the shelf button is then
  highlighted; a disabled button that leads nowhere would otherwise be a dead end.
- **My shelf** has a three-way switch — Books, TV, Films — built as three stacked `BigButton`s, the
  shape the Tracks size toggle settled on (`PLAN-phase-9-tracks.md` §6, PR 8). Below it, each series
  is a heading with an *I've read them all* (or *watched*) button, and each title a full-width tile
  carrying a tick, the series' icon and colour, and the title's name. A tick toggles on tap and is
  written through `ProgressRepository` with §5.3's 500 ms debounce. A tile shows the title's best
  score, if any, as stars.
- **Pick one** lists offered titles in the same groups, ticked titles first within each series, with
  the best score beside each. Picking an unticked title is allowed: the child chose it.
- **Play** shows the question, three answer `BigButton`s, a progress row of ten dots, and a quit
  button with the same confirmation the arcade's `GameShell` uses. After an answer, the buttons lock,
  the right one shows a tick in the theme's success colour, a wrong choice shows in the theme's
  `wrong` colour with no cross, and **Next** appears. No auto-advance: reading the right answer takes
  as long as it takes.
- **Round end** reuses `CompletionCard` and `Confetti` from `core/ui/` with the score as *7 out of
  10* and stars, `backLabel` *Back to Quiz*, and a *Play again* that starts a new round of the same
  kind. Confetti plays for every finished round (§1: no failure state).
- **Sound and haptics** reuse existing motifs, so no asset is added: `sudokuCorrect` for a right
  answer, `sudokuWrong` at half gain for a wrong one — the soft bump Tracks uses for a refused stroke
  — and `sudokuComplete` at round end; `AppHaptics.tap()` on a right answer and nothing on a wrong one, because `mistake()` is a buzz and
  a wrong answer here is not an error.
- Routes: `/quiz`, `/quiz/shelf`, `/quiz/pick` and `/quiz/play` (pushed with a `QuizPlayArgs` naming
  a title id or *mixed*). `layout_sweep_test.dart` gains all four.

### 4.6 The round

`QuizRound` and `QuizPicker` live in `features/quiz/model/`, import nothing from Flutter, and are
tested with plain `test()` calls.

**One title's order.** A title's offered questions, sorted by id, are shuffled by `GameRng(seed)`
with Fisher–Yates. The profile stores, per title, `seed`, `next` (how many of that order have been
asked) and `pool` (how many questions the order was built over). The next question is
`order[next]`; when `next` reaches `pool`, a new `seed` is drawn and `next` returns to 0. If the
loaded pool size differs from the stored `pool` — questions were added, checked or withdrawn — `next`
resets to 0 under the same seed. So **no question repeats until every question of its title has been
asked**, for two integers and a seed per title. Determinism here is convenience, not load-bearing as
it is for puzzles: if `GameRng`'s sequence ever changed, the cost is a few repeats.

**A single-title round** takes the next ten from that title's order. With `minQuestionsPerTitle`
equal to the round length, a round never repeats a question within itself.

**A mixed round** takes ten questions from ticked, offered titles, rotating **by series first, then
by title within a series**, each series and each title order shuffled per round. Rotating by series
stops a child who has ticked thirteen Dahl books and one Narnia book getting thirteen Dahl questions
in fourteen; rotating by title within a series spreads a round across the books. Each draw advances
that title's `next`, so mixed and single-title rounds share one order per title and neither repeats
what the other just asked.

**Within a round**, questions are ordered level 1 before level 2, so a round starts with its easiest
questions. Options are the right answer plus two of the three wrong ones, chosen and shuffled by a
round `GameRng` seeded from the clock, as an arcade run is.

**Scoring.** The round counts right answers. Nothing else is scored.

**`GameRng` moves to `core/game_rng.dart`** in PR 5, unchanged, with its test. It was kept inside
`features/arcade/shared/` because the arcade was its only user (`game_rng.dart`); a second feature is
the point at which it moves, as `fixed_step.dart` moved when a second game needed it
(`PLAN-phase-7-snake.md` §4.7). The literals pinned in `game_rng_test.dart` do not change, which is
the proof the move changed nothing.

### 4.7 Save fields

```json
"quiz": {
  "known": ["dahl.matilda", "narnia.lion-witch-wardrobe", "cbeebies-bluey.bluey"],
  "titles": {
    "dahl.matilda": { "seed": 912873, "next": 14, "pool": 24, "rounds": 3, "best": 9 }
  },
  "mixed": { "rounds": 5, "best": 8 }
}
```

- `Profile.quiz`, a `QuizProgress`, default empty. On the profile because siblings on one tablet have
  read different books.
- `known` is the ticked title ids, written sorted so the file does not churn with set order. An id
  the build does not know — from a later build, or a withdrawn title — is **kept**, not dropped,
  unlike `tracksTheme`'s unknown value: dropping it would untick a child's book when a players file
  passes through an older build.
- `titles` holds §4.6's `seed`, `next` and `pool`, plus `rounds` (finished single-title rounds) and
  `best` (best single-title score, 0–10). `mixed` holds the same two counters for mixed rounds. An
  entry with a negative number or `next` beyond `pool` is dropped silently, so that title starts a
  fresh order — the handling Tracks gives a malformed board (`PLAN-phase-9-tracks.md` §4.11).
- **Written at the end of each round, on quitting a round, and on each shelf toggle**, not per answer
  (§2). Quitting writes the `next` values the answered questions advanced, so a child who quits after
  one question is not asked it again first next time; a force-quit loses at most that round's
  advance, which costs a few repeats.
- `schemaVersion` stays 1: the field is optional with a default, the reasoning phases 3, 4, 7, 8 and
  9 recorded. `transfer_codec.dart` nests the save codec's output, so a players file carries it
  unchanged; `ProfileImportEntry.result` builds a profile field by field, and the guard test phase 9
  added (`PLAN-phase-9-tracks.md` §6, PR 4) fails until `quiz` is added there too — which is that
  test doing its job.

### 4.8 Text size and layout

The 100- and 30-character caps are guesses until measured. PR 6 adds a widget test that renders the
play screen at 200 % text on a 360 x 640 dp window with the longest question and the three longest
answers in the real bank, and asserts no overflow and that all three answers and Next are on screen
without scrolling. If the caps do not fit, the caps come down — in the content test, so every pack is
held to them — rather than the screen scrolling, because an answer below the fold is an answer a
child does not know exists.

### 4.9 Store and private builds

**The directory is the audience.** `app/pubspec.yaml` declares the two directories differently:

```yaml
flutter:
  assets:
    - assets/quiz/store/
    - path: assets/quiz/private/
      flavors:
        - private
```

Flutter bundles a flavour-tagged asset only into a build of that flavour, so every build made
without `--flavor private` leaves the private directory out of its asset bundle entirely. Both
directories always hold an `index.json`, because a declared asset directory that is empty fails the
build (`app/pubspec.yaml`).

**Flavours exist on Android only.** `app/android/app/build.gradle.kts` gains a flavour dimension,
`audience`, with two product flavours:

- `store`, changing nothing — the application id, label and signing stay as they are.
- `private`, with `applicationIdSuffix = ".home"` and the label *Zibo Games (home)*, so it installs
  beside the store build rather than over it and is never mistaken for it. The cost is a separate
  save on the same device; a players file moves a child between them (`PLAN-transfer.md`). §9 asks
  whether the owner wants that or one shared app id.

Once Android has product flavours, a `flutter build apk` with no `--flavor` no longer finds a single
APK, so CI and `README.md` pass `--flavor store` and the artifact becomes `app-store-release.apk`.
Every reference to `app-release.apk` — `android-apk.yml`, the usage comments in
`check_apk_permissions.sh` and `apk_signing_cert.sh`, `README.md` — moves with it in the same pull
request. PR 3 records what an unflagged Android build does in practice; if it quietly produces a
private build rather than failing, PR 3 fixes that before merging, because the safe direction for a
forgotten flag is the store.

iOS, macOS, Linux and Windows declare no flavours and build without `--flavor` — `flutter build
linux` and `flutter build windows` do not accept one in Flutter 3.44 — so they are always store
builds, and CI's existing legs for them change nothing. No `default-flavor` entry goes in
`pubspec.yaml`, because it would apply to iOS and macOS too and demand Xcode schemes that do not
exist (§3).

**What the app knows.** Content is decided by what is bundled, not by a flag the code reads, so
there is one mechanism rather than two that could disagree. The one runtime use of the flavour is
the settings footer, which appends *home build* when `appFlavor` (`package:flutter/services.dart`)
is `private`, so the owner can tell which build a tablet has.

**The check.** `tool/check_quiz_audience.sh <apk> store|private` lists the APK with `unzip -l`. In
`store` mode it fails on any `flutter_assets/assets/quiz/private/` entry; in `private` mode it fails
if there is none, which proves the flavour mechanism bundled them rather than letting the store check
pass vacuously. Its `--self-test` runs both modes against canned listings, per `AGENTS.md`'s rule
that a guard needs its own test. `android-apk.yml` builds both flavours and checks both; it uploads
the store APK as now, and the private APK only on a `workflow_dispatch` run that asks for it.
`android-release.yml` attaches only the store APK to a release.

**What this does not do.** It keeps private packs out of the store's binary; it does not make them
secret. This repository is public, so the private packs' JSON is readable on GitHub, and an Actions
artifact on a public repository can be downloaded by any signed-in GitHub user. If the owner wants
the content itself private, the private directory's *source* moves — a gitignored local directory,
or a private repository checked out into it — and nothing in the app or the build changes, because
the build reads a path. §9 holds the choice.

---

## 5. Repository layout

```
app/assets/quiz/
  store/                          # in every build (§4.9)
    index.json                    # series in shelf order, withdrawn titles
    fairy-tales.json, aesop.json, classic-stories.json
  private/                        # only in `--flavor private` builds
    index.json
    faraway-tree.json, narnia.json, dahl.json, rainbow-magic.json, kitty.json
    cbeebies-bluey.json, cbeebies-topsy-and-tim.json, cbeebies-hey-duggee.json,
    cbeebies-witch-detectives.json, cbeebies-waffle.json
    disney-mickey.json, disney-frozen.json, disney-princesses.json
app/android/app/build.gradle.kts  # the `audience` dimension: store and private flavours
tool/check_quiz_audience.sh       # no private pack in a store APK; some in a private one
app/lib/core/game_rng.dart        # moved from features/arcade/shared/ (§4.6)
app/lib/features/quiz/
  model/                          # QuizCatalog, QuizQuestion, QuizPicker, QuizRound — no Flutter
  data/                           # QuizCatalogLoader (rootBundle, kReleaseMode filter), providers
  ui/                             # quiz menu, shelf, title list, play screen
app/test/features/quiz/
  content_test.dart               # §4.3, over the real bank
  fixtures/                       # one deliberately broken pack per content rule
app/integration_test/quiz_smoke_test.dart
```

Packs are one per series rather than one file per collection so a content pull request touches only
its own series' file, and two can be written in parallel without conflicting. CBeebies and Disney
series get a file each for the same reason, and because Disney is three unrelated series. `model/`
imports nothing from Flutter so the round logic is tested in plain `test()` and runs in milliseconds;
the loader, which needs `rootBundle`, is the only part of the catalog in `data/`.

---

## 6. Pull requests

Estimates assume one developer, or one agent session with review, working on this full time, as
phase 9's did. **Checking content is separate and is the owner's time**: verifying a question, its
answer and its three wrong answers against the book or episode takes about two to three minutes with
the source to hand, so the launch threshold of 470 checked questions is roughly 16–24 hours, and the
full target of 940 twice that. The general packs add 100 checked questions, about four hours. That is the phase's real critical path, and why the release line does
not wait for it.

| PR | Title | Estimate |
|---|---|---|
| 1 | This plan | — |
| 2 | Pack format, loader, content test, and the Faraway Tree pack | 1.5–2 days |
| 3 | Store and private builds | 1–1.5 days |
| 4 | Save field and transfer round trip | 0.5–1 day |
| 5 | The round model, and `GameRng` moved to `core/` | 1–1.5 days |
| 6 | The screens and the Quiz card | 2–3 days |
| 7 | Narnia | 1 day drafting |
| 8 | Roald Dahl | 1.5 days drafting |
| 9 | Rainbow Magic and Kitty | 1 day drafting, after §9's Kitty question |
| 10 | CBeebies | 1 day drafting |
| 11 | Disney | 1.5 days drafting |
| 12 | General packs for the store | 1 day drafting |
| 13 | Smoke test, device pass and close | 0.5–1 day, plus device time |

Total 13–18 working days of building and drafting, plus checking. PR 6 is the widest because §4.8's
measurement may move the caps and the shelf is the first screen in the app that scrolls a long list.
Content pull requests 7–12 depend only on PR 2 and can be built in any order or in parallel; their
order here is the ask's, books before screens.

**PR 1 — this plan.** `PLAN-phase-10-quiz.md`, and a phase 10 entry in `PLAN.md` §7.
**Done when:** both are on `main`, and §9's placement question is answered before PR 6 starts.

**PR 2 — format, loader, content test, first pack.** `QuizCatalog`, `QuizQuestion`,
`QuizCatalogLoader`, both `index.json` files, `private/faraway-tree.json` with 20 drafted questions
per book, the content test and its broken fixtures, and both directories declared in `pubspec.yaml`
as §4.9 shows — the private one flavour-tagged from its first commit, so no build ever carries it
untagged, even before PR 3 gives Android the flavour that can bundle it.
**Done when:** `flutter test test/features/quiz` passes; each content rule of §4.3 fails against its
fixture (shown in the PR description); a loader test in release mode drops an unchecked question and
hides a title with nine checked; a pack with a syntax error is skipped and the others still load;
the coverage table is in the PR description; the parse time of the bank, scaled to 940 questions, is
recorded in §8.

**PR 3 — store and private builds.** The two Android product flavours, `--flavor store` in CI and
`README.md`, the `app-store-release.apk` rename everywhere, `tool/check_quiz_audience.sh` with its
self-test, the private build and check in `android-apk.yml`, and the footer's *home build* (§4.9).
**Done when:** the store APK from CI passes `check_quiz_audience.sh store` and the private APK passes
`check_quiz_audience.sh private`; each fails the other's mode (shown in the PR description);
`--self-test` passes; `grep -rn 'app-release.apk' .github tool README.md` prints nothing; CI's
iOS, macOS, Linux and Windows legs are green with no change to their commands; the private APK's
`aapt dump badging` shows the `.home` id and the *Zibo Games (home)* label; what an unflagged
`flutter build apk` does is recorded in §4.9; a footer widget test shows *home build* for `private`
and nothing for `store` or no flavour.

**PR 4 — the save field.** `QuizProgress`, `QuizTitleProgress`, codec, equality, and `quiz` in
`ProfileImportEntry.result`.
**Done when:** a save written before this PR decodes with `quiz` empty (a fixture test, as
`preTracksSaveJson` is for Tracks); a profile with ticks and counters round-trips through the save
codec and through a players file unchanged; an unknown title id in `known` survives a round trip; an
entry with `next` greater than `pool` is dropped and the rest load; the import guard test fails
before `quiz` is added to the import and passes after; `schemaVersion` is still 1.

**PR 5 — the round.** `QuizPicker`, `QuizRound`, and `game_rng.dart` moved to `core/`.
**Done when:** plain `test()` cases show that a title of 24 questions asks all 24 before any repeats,
over three cycles; a changed `pool` restarts the order; a single-title round never repeats a question
within itself; a mixed round over one ticked Narnia book and thirteen ticked Dahl books draws at
exactly five Narnia questions out of ten, the series alternating; every level-1 question in a round precedes every level-2 one;
each question's three options are distinct and include the answer; `game_rng_test.dart` passes with
its literals unchanged; `no_random_test.dart` still passes.

**PR 6 — the screens.** The Quiz menu, shelf, title list and play screen, the Quiz card on the Puzzles
menu, routes, sounds and haptics.
**Done when:** a widget test plays a ten-question round to the round-end card and sees the score
written to the save; ticking a title on one profile leaves another profile's shelf unchanged; *Quiz
me* is disabled with nothing ticked and enabled after one tick; `layout_sweep_test.dart` passes with
the four new routes; §4.8's longest-content test passes at 200 % text on 360 x 640 dp; the Puzzles
menu shows three cards in portrait and landscape; screenshots of the shelf and a question, day and
night, are attached to the PR rather than committed. The app version moves to 0.5.1, the first build
in which a child can reach the quiz.

**PRs 7–12 — content.** Each adds its series' packs at 20 drafted questions per title, with
`checked: false` on everything not yet verified, and pastes the coverage table. A follow-up commit or
pull request by the owner flips `checked` as questions are verified; corrections go in the same
commit as the flip.
**Done when (each):** the content test passes; every title in the pull request has 20 questions with
at least 6 at level 1; the coverage table is in the description; no title id outside the pull
request's series changed (`git diff --stat` touches only its own files and `index.json`).

**PR 12 — general packs for the store.** `store/fairy-tales.json`, `store/aesop.json` and
`store/classic-stories.json` with the titles §9 settles, at 20 drafted questions each. The same
done-when as PRs 7–11, plus a loader test over the real store directory: with every question
unchecked the store catalog offers nothing and the Puzzles menu shows no Quiz card (§4.5); with ten
of one title's questions checked, it offers that title and the card appears.

**PR 13 — smoke test, device pass, close.** `app/integration_test/quiz_smoke_test.dart` drives home,
Puzzles, Quiz, the shelf, a tick, *Quiz me* and a full round to the round-end card, and checks the
round in a real `save.json`. The device checks of §8. This file gets a closed banner; `PLAN.md` §5.2,
§6 and §7 are reconciled with what was built; `README.md` names the game. The app version moves to
0.6.0.
**Done when:** the smoke test passes on at least one device, named in the pull request; every
*(Device)* line in §8 is ticked or recorded as unmet with the reason; the coverage table at close is
copied into §8, with every title under the threshold named — those are hidden, not blockers.

---

## 7. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| A wrong fact reaches a child as a "right answer" | High | §1's gate: release builds load only `checked` questions, the loader test proves it, and `checked` is flipped only with the source to hand. `source` names where each answer is, so a reported error is rechecked in minutes. A wrong answer found after release is fixed by correcting or unchecking the question in the next build; no save holds a question (§3). |
| Content volume stalls the phase | High | The release line is PR 13 regardless of coverage; a title under ten checked questions is hidden, not a blocker. Content PRs depend only on PR 2 and can run in parallel. §6 states the checking hours so the owner can plan them rather than discover them. |
| A trademark or copyright complaint, or a store rejecting the listing | Medium | Every named series starts private and is not in a store build (§4.4, §4.9); the store gets public-domain stories unless the owner moves a pack. Text only, original wording, no art, logos, stills, tunes or long quotations (§1); the content test bounds text length and refuses non-JSON assets. The store listing names no series. This plan does not claim any of it is legally safe (§9). |
| A private pack ships in a store build | High | The directory is the audience and is flavour-tagged from its first commit (PR 2); only `--flavor private` bundles it; `check_quiz_audience.sh` fails CI on a private entry in the store APK and on none in the private APK, so a broken mechanism cannot pass by finding nothing; the script has a self-test. Non-Android targets declare no flavour and cannot build a private variant. |
| Private content is assumed secret and is not | Medium | No mitigation in the build, by design: the repository is public and so is its JSON (§4.9). Stated in §4.9 and asked in §9; if the owner wants it secret, the private directory's source moves and nothing else does. |
| Adding flavours breaks an existing build or a habit | Medium | Android only; PR 3's done-when requires the other four CI legs green with unchanged commands and every `app-release.apk` reference moved; an unflagged Android build's behaviour is checked and made to fail or build the store rather than the private variant. |
| A question spoils a book the child has not read | Medium | One title per question, the latest a reader needs (§4.1); mixed rounds draw only from ticked titles (§4.6). Review is the only check on which title a question belongs to; no mechanism can judge it. |
| The text is too much for the youngest players | Medium | Three options; length caps enforced by the content test and measured in PR 6 (§4.8); level-1 questions first in every round; the screen reader reads it all. Proven only by §8's device line with a six-year-old. |
| Questions repeat so often a child is bored | Low | §4.6's per-title order asks every question before any repeat; PR 5's test proves it over three cycles. |
| A pack ships malformed and the quiz breaks on a device | Low | The content test in CI; the loader skips a bad pack and keeps the rest (PR 2's test). |
| Renaming a title id unticks it on every shelf | Medium | Ids are frozen once shipped (§3); withdrawal is the only removal (§4.1). The content test cannot know what shipped, so PR 13 adds a test pinning every title id that exists at the close: removing or renaming one then fails the build. |
| An ambiguous series is drafted wrongly (Kitty, *Witch Detectives*) | Medium | Both are open questions in §9 that block only their own content pull requests. Nothing is drafted for either until the owner names the series. |
| The shelf is too long to scroll comfortably on a phone | Low | Grouped by collection behind a three-way switch, so the longest list is Books at about 27 titles; *I've read them all* per series. Checked in §8. |

---

## 8. Verification checklist

- [ ] `cd app && flutter test test/features/quiz` passes, including the content test over the real
      bank; each content rule fails against its broken fixture. *(PR 2.)*
- [ ] The loader in release mode drops every unchecked question and hides a title below ten checked
      (loader test). *(PR 2.)*
- [ ] Bank parse time, scaled to 940 questions, recorded here: ___ ms on the CI runner. *(PR 2.)*
- [ ] `tool/check_quiz_audience.sh store` passes on CI's store APK and fails on its private APK, the
      reverse holds in `private` mode, and `--self-test` passes. *(PR 3, and every CI run after.)*
- [ ] `grep -rn 'app-release.apk' .github tool README.md` prints nothing. *(PR 3.)*
- [ ] A save from before PR 4 loads on the PR 13 build with `quiz` empty (fixture test in
      `save_codec_test.dart`).
- [ ] `game_rng_test.dart` passes with its literals unchanged after the move to `core/`; `git log -p
      -- app/test/**/game_rng_test.dart` shows only the path change. *(PR 5.)*
- [ ] `dart tool/check_offline.dart` passes and `git diff <plan commit> -- '*/pubspec.yaml'` shows only
      the `version:` line and the `assets/quiz/` declaration.
- [ ] `layout_sweep_test.dart` covers `/quiz`, `/quiz/shelf`, `/quiz/pick` and `/quiz/play`, and the
      longest-content test passes at 200 % text on 360 x 640 dp. *(PR 6.)*
- [ ] `tool/verify.sh` time before and after the phase recorded here: before ___, after ___.
- [ ] The coverage table at the close is copied here, with every title under the threshold named.
- [ ] A test pins every title id that exists at the close. *(PR 13.)*
- [ ] *(Device)* `quiz_smoke_test.dart` passes on an Android phone; device named in PR 13.
- [ ] *(Device)* A six-year-old who has read or watched one launch title finds it on the shelf, ticks
      it and plays a round unaided after one demonstration.
- [ ] *(Device)* At 200 % system text on a 360 dp phone, every answer of every question in one round
      of each collection is readable without scrolling.
- [ ] *(Device)* TalkBack reads a question and its three answers in order, and announces which answer
      was right.
- [ ] *(Device)* A players file exported with ticks and scores imports on a second device with the same
      shelf and best scores.
- [ ] *(Device)* Rotating mid-round keeps the round, its question and its score so far.
- [ ] *(Device)* On one Android tablet, the store and private builds install side by side; the store
      build's shelf shows only store series, the private build's shows both, and its settings footer
      says *home build*.

---

## 9. Open questions

| Question | What resolves it |
|---|---|
| **Which "Kitty detective" series?** Paula Harrison's *Kitty* books, the best-known match, are about a girl with cat-like superpowers rather than a detective; other candidates exist. The plan will not guess. | The owner names the author and titles. Blocks Kitty's half of PR 9 only. |
| ***Witch Detectives*** — confirm the exact title and channel, and which series of it. | The owner. Blocks that title in PR 10 only. |
| **Placement.** A third card on the Puzzles menu (this plan's default, §3) or a fourth card on the home screen. A quiz is not a puzzle, which argues for home; three cards is the owner's phase-9 choice, which argues for Puzzles. | The owner, before PR 6. A fourth home card means redesigning the landscape row as a 2 x 2 grid in PR 6, about a day more. |
| The game's label. "Quiz" is the working name and the route prefix; the label is not frozen. | The owner. Held in one constant, as `tracksMenuTitle` is. |
| Which Rainbow Magic sets beyond the first three, and whether per-book ticks are wanted after all (§2). | The owner; per-book ticks multiply that series' content by seven. |
| Which Roald Dahl books stay in the thirteen, which Disney films, and what *Mickey* covers (*Mickey Mouse Clubhouse*, *Mickey Mouse Funhouse*, the classic shorts). | The owner, before PRs 8 and 11. |
| *Topsy and Tim* began as Jean and Gareth Adamson's books. TV only, as the ask lists it, or a book series too? | The owner. TV only until told otherwise. |
| Narnia's order: current numbering (*The Magician's Nephew* first) or publication order (*The Lion, the Witch and the Wardrobe* first). It decides which title a series-wide question belongs to (§4.1). | The owner, before PR 7. |
| Which series, if any, move from private to the store. All start private (§4.4). | The owner, per series, at any time: a `git mv` between the two directories, keeping title ids and every child's ticks. Advice is the owner's to seek; the plan does not claim naming a series in a store build is legally safe. |
| Which general packs the store build carries — §4.4 proposes fairy tales, Aesop and three classic stories. | The owner, before PR 12. |
| Should private content stay in this public repository? It keeps it off the store, not off GitHub (§4.9). | The owner. Options: leave it (default); a gitignored local directory, so only the owner's own machine can make a private build; a private repository checked out into the directory, so CI can still check it; or §3's on-device import, which needs no private build at all. Only the first is in this plan's estimates. |
| One app id for both builds, or the private build as a separate `.home` app (§4.9's default)? | The owner, before PR 3. One id means one save, but only one build can be installed at a time, and a store-signed build and a self-signed one cannot replace each other without an uninstall, which deletes the save. |
| Who checks the questions, and are 10 to offer and 20 as the target the right numbers? | The owner. Both are constants. |
| Built-in read-aloud for non-readers (§2). | Deferred; the device pass shows whether the screen reader is enough. |
| A per-profile *harder questions* switch using `level` (§2). | Deferred; the device pass shows whether one level mix suits both a five- and a nine-year-old. |
| Two players taking turns (§2). | Deferred. |

---

## 10. Starting order

1. Answer §9's Kitty, placement and app-id questions; they are the only ones that block a pull
   request in the first half of the phase.
2. PR 2: the content test and its broken fixtures **before** the loader, so the format is enforced
   before any pack depends on it; then the Faraway Tree pack, which is the first real input.
3. PR 4 and PR 5 in either order, then PR 6. Start content drafting (PRs 7–12) as soon as PR 2 is
   merged, and start checking as soon as the first pack is drafted: checking is the critical path
   (§6), and every hour of it done before PR 13 is a title a child can play at release.
