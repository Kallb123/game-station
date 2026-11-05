# Phase 10 — Quiz, trivia about children's books, TV and films

This file is the design and the pull-request breakdown for a fifth game: a multiple-choice quiz about
the stories a child knows. A child ticks the books they have read and the shows and films they have
watched on a shelf, then either plays a mixed round drawn from everything ticked or picks one title
and is quizzed on that alone. Books come first — Enid Blyton's Magic Faraway Tree, Roald Dahl,
Rainbow Magic, Narnia and Paula Harrison's Kitty — then CBeebies (Bluey, Topsy and Tim, Hey Duggee,
Waffle the Wonder Dog) and Disney (Mickey and friends, Disney films, Pixar films). It is a third
card on the Arcade menu, after Invaders and Snake.

**Two builds, two audiences.** Every pack is either *store* or *private*, decided by which directory
it sits in. A store build — any build not made with the private flavour — carries only store packs; a private
build, made with `flutter build apk --flavor private`, carries both. Both are the same app: the
private build reaches the family's own tablets through the Amazon Appstore's testing track, and the
store build through the public listing. So the named series can be played at home without being
released to the public, while Peter Rabbit and general knowledge — the world, the UK, animals — go to
both (§4.4, §4.9).

[`PLAN.md`](PLAN.md) is the source of truth for the project; §7 there carries a one-paragraph entry
for this phase pointing here. Where this file and `PLAN.md` disagree, the reason is stated here and
the closing pull request reconciles `PLAN.md`. Read [`PLAN-phase-9-tracks.md`](PLAN-phase-9-tracks.md)
§4.11 first: this phase adds save fields the way Tracks did. Its card on the Arcade menu takes the
shape [`PLAN-phase-7-snake.md`](PLAN-phase-7-snake.md) §4.9 gave that menu's cards.

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
| A question never spoils a title the child has not ticked | Narnia, Faraway Tree and Rainbow Magic are series, and a question about book four answered on the strength of book one gives book four away. Every question belongs to exactly one title — the earliest a reader would need to answer it — and a mixed round draws only from ticked titles (§4.1, §4.6). Disney's three titles each span many films, so they ask only what a film's opening shows, never how it ends (§4.4). |
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
| One tick per Rainbow Magic book | Rainbow Magic has more than two hundred books in sets, mostly of seven. A tick per book is a shelf of hundreds and a content job of thousands of questions. The set is the title (§4.1), as the owner confirmed. |
| One tick per Disney or Pixar film | The owner asked for general questions. Three broad titles keep the shelf short; a film-by-film list is dozens of titles to tick and to fill. A film that earns its own title later is a content-only addition (§4.4). |
| *Witch Detectives* | Left out by the owner: it may be too new to have much to ask about. A content-only addition later, as `cbeebies-witch-detectives`, if wanted. |
| One tick per TV episode | The same arithmetic for Bluey and Hey Duggee. A show is one title. |
| Every Roald Dahl book, every Narnia book, every Rainbow Magic set | §4.4 names the owner's launch list. More titles are content-only pull requests later, needing no code. |
| Adaptive difficulty or a per-profile age setting | Questions are tagged with a level now, because tagging hundreds later is the expensive part, and a round orders easier questions first (§4.6). A per-profile *harder questions* switch is §9's. |
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
   and the Quiz card on the Arcade menu.
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
| Questions as Dart `const` tables, as the sprites are | Type-checked and needing no parse, but several hundred multi-line literals are what `dart format` reflows on every edit, so a one-word correction becomes a noisy diff. Content would also be reviewable only by someone reading Dart. The parse failure JSON allows is covered instead by the content test in CI and a loader that skips a bad pack (§4.2). |
| YAML packs (`package:yaml`) | Kinder to hand-edit, but a dependency to add and audit for a format JSON already covers. |
| `drift` or SQLite for the questions | A database for under a megabyte of read-only text that is read once at startup. |
| Generating questions on the device with a language model | No network (`PLAN.md` §1), a model too large to bundle, and an unchecked fact on every screen — the opposite of §1's first constraint. |
| Remembering every asked question id in the save | §3's load-bearing decision; replaced by a per-title shuffled order and a position in it (§4.6), two integers per title. |
| A fourth card on the home screen | The owner chose a Puzzles menu in phase 9 to keep the home screen at three cards, because a fourth forces the landscape row into a 2 x 2 grid (`PLAN-phase-9-tracks.md` §3). |
| A third card on the Puzzles menu | This plan's first default. A quiz is not a puzzle, and the owner put it on the Arcade menu instead (§4.5), whose cards already stack in a scrolling column, so a third needs no new layout. |
| The quiz's code under `features/arcade/` | The card is on the Arcade menu, but the quiz shares none of the arcade's machinery — no fixed step, no `GameShell`, no control pad, no `HighScore` table — except `GameRng`, which moves to `core/` (§4.6). It is its own feature, `features/quiz/`, and the card is the one arcade file it touches. |
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
collection   book | tv | film | topic     fixed in code; sets the tick's word and the icon
  series     dahl, narnia, cbeebies-bluey …    one JSON file each, in shelf order
    title    dahl.bfg, narnia.prince-caspian … what a child ticks and what a question belongs to
```

- A **title** is the unit a child ticks and picks: one book (*Matilda*), one Rainbow Magic set (*the
  Rainbow Fairies*), one show (*Bluey*), one group of films (*Pixar films*), or one
  general-knowledge topic (*Animals*). For a show, the series and the title are the same thing, and
  the series file holds one title.
- A **topic** is a title with no story behind it. It is ticked like any other — the tick reads *quiz
  me on this* rather than *read* or *watched* — so a mixed round draws from it only if the child
  chose it. Reading order and §1's spoiler rule do not apply to topics.
- A **title id** is `<series>.<slug>`, lowercase ASCII letters, digits and hyphens, matching
  `^[a-z0-9-]+\.[a-z0-9-]+$` (CBeebies series are named `cbeebies-bluey`, so the id keeps one
  dot). Frozen once shipped (§3). A title that must go is **withdrawn**, by listing its id in
  `withdrawnTitles` in the catalog, never by deleting or renaming it: a withdrawn title stays ticked
  in saves and is simply not shown, so restoring it later restores every child's tick.
- Titles in a series are in **reading order**, and the series' shelf order is the catalog's. Narnia's
  two launch books, *The Lion, the Witch and the Wardrobe* then *Prince Caspian*, are in that order
  under both the current numbering and publication order; the choice between them is §9's, and
  matters only once *The Magician's Nephew* or *The Horse and His Boy* joins. Order matters for one
  rule: a question that needs more than one title belongs to the latest of them, so it is asked only
  of a child who has reached it; a question about the series as a whole ("Who made Narnia?") belongs
  to the earliest title that answers it.

### 4.2 Pack format and loading

One file per series under `app/assets/quiz/store/` or `app/assets/quiz/private/` (§4.9), and one
index in each directory listing its packs in shelf order:

```json
// app/assets/quiz/private/index.json
{ "format": 1,
  "series": ["faraway-tree", "narnia", "dahl", "rainbow-magic", "kitty",
             "cbeebies-bluey", "cbeebies-topsy-and-tim", "cbeebies-hey-duggee",
             "cbeebies-waffle", "disney"],
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
- `source` says where the answer is — a chapter, an episode or scene, or for a topic a named
  reference work such as an atlas or encyclopedia — so a checker can find it and a later reader can
  recheck it. Text only; no URL (§1).
- A topic question asks only for facts that do not change: a capital city, a continent, what a
  hedgehog eats — never a population, a record, a ruler or an office holder. A fact that changes
  turns a checked question wrong with no edit to the pack. This is the reviewer's rule; the content
  test cannot judge it.
- Question ids are `<title id>.<three digits>`, unique across the bank, never reused. They exist for
  review and for the content test, not for the save (§3).

**Loading.** `QuizCatalogLoader` reads `store/index.json`, then `private/index.json` if the build
carries it, and each listed pack through `rootBundle`, once, during app start beside the save, so the
Arcade menu knows whether to show the Quiz card (§4.5). It parses with `dart:convert` and builds an immutable `QuizCatalog`. A
pack that fails to parse or validate is skipped and logged with `debugPrint`, never shown to a child
(`AGENTS.md`); the content test makes that a CI failure long before a device sees it. Release builds
(`kReleaseMode`) drop every question with `checked: false` at load; debug and profile builds keep
them and mark them with a small *unchecked* chip on the play screen, so the owner can play-test a
draft pack. `offeredTitles` returns the titles with at least `minQuestionsPerTitle` (10) loaded
questions that are not withdrawn.

The whole bank at the launch target (§4.4) is about six hundred questions with the store packs, plus
twenty per Kitty book — well under 300 KB of JSON.
Parsing it is a few tens of milliseconds; PR 2 measures it, and if it exceeds 100 ms on the CI runner
the parse moves to `compute`.

### 4.3 The content test

`app/test/features/quiz/content_test.dart` reads both `app/assets/quiz/store/` and
`app/assets/quiz/private/` with `dart:io`, whatever flavour the test runs under, and fails on:

- a file in either directory that is not in that directory's `index.json`, an index entry with no
  file, a non-`.json` file, or anything in `app/assets/quiz/` outside the two directories;
- a series in both directories;
- a pack that does not parse, a missing or mistyped field, or a `format` other than 1;
- a series id that is not its file name, or a `collection` other than `book`, `tv`, `film` or `topic`;
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

Content targets: **20 questions per title, 40 for a broad title, at least 10 checked to be
offered.** The list is the owner's. **Every series in this table starts private** (§4.9): moving one
to the store is a deliberate `git mv` by the owner, never a default.

| Collection | Series | Titles | Count | Target |
|---|---|---|---|---|
| Book | The Magic Faraway Tree (Enid Blyton) | *The Enchanted Wood*, *The Magic Faraway Tree*, *The Folk of the Faraway Tree*, *Up the Faraway Tree* | 4 | 20 each |
| Book | The Chronicles of Narnia (C. S. Lewis) | *The Lion, the Witch and the Wardrobe*, *Prince Caspian* — for now; the other five are later content | 2 | 20 each |
| Book | Roald Dahl | *James and the Giant Peach*, *Charlie and the Chocolate Factory*, *The BFG*, *Matilda* — in publication order | 4 | 20 each |
| Book | Rainbow Magic | *The Rainbow Fairies* (the colour fairies) and *the Weather Fairies*, one title per set of seven | 2 | 20 each |
| Book | Kitty (Paula Harrison) | One title per book, in publication order from *Kitty and the Moonlight Rescue* (2019). A dozen or more are out; PR 9 takes the list from Oxford University Press's and the owner trims it to the books the family has | per PR 9 | 20 each |
| TV | CBeebies | *Bluey*, *Topsy and Tim*, *Hey Duggee*, *Waffle the Wonder Dog* (the ask's *Waffle the Dog*) — one title each | 4 | 20 each |
| Film | Disney | *Mickey and friends*, *Disney films*, *Pixar films* — general questions, three broad titles | 3 | 40 each |

That is 19 titles before Kitty: 440 questions at target and 190 checked to offer them all, plus 20
to draft and 10 to check per Kitty book.

*Wonka* is read as *Charlie and the Chocolate Factory*, the Dahl book Willy Wonka is from; *Charlie
and the Great Glass Elevator*, and the 2023 film *Wonka*, which is not Dahl's, are content-only
additions if wanted. *Topsy and Tim* is TV only, as the ask lists it.

**Disney's titles are broad.** The owner asked for general questions about Mickey and friends and
about other Disney titles, Pixar's included, rather than a title per film:

- *Mickey and friends* covers Mickey, Minnie, Donald, Daisy, Goofy and Pluto across the classic
  shorts and the current shows, asking only what holds across them — who is whose friend, Pluto is
  a dog — never an episode's plot.
- *Disney films* covers Walt Disney Animation's films, starting with the ones the ask named: *Frozen*,
  *Frozen II* and the Princess films. *Pixar films* covers Pixar's: *Toy Story*, *Finding Nemo*,
  *Monsters, Inc.*, *Cars*, *Inside Out* and the like.
- A broad title spans films a child may not have seen, so §1's spoiler rule becomes a reviewer's rule
  for it: **a question asks only what a film's opening shows** — who the characters are, where it is
  set, what they want — never a twist or an ending. `source` names the film.
- Broad titles target 40 questions, as topics do, for the same reason (below): a child plays them
  far more often than a single book.
- A film that later earns its own title — the child wants *Frozen* alone — is a new title in
  `disney.json`, with the questions about it moved into it under new ids. The broad title's id stays.

**Store packs.** The owner's choice: Peter Rabbit, and general knowledge about the world, the UK and
animals.

| Collection | Series | Titles | Count | Target |
|---|---|---|---|---|
| Book | Beatrix Potter | *The Tale of Peter Rabbit* | 1 | 20 |
| Topic | General knowledge | *Animals*, *The UK*, *The world* | 3 | 40 each |

Topics target 40 questions rather than 20 because they have no spoiler limit and no book to finish,
so a child can play them far more often, and a larger pool goes longer before it repeats (§4.6).
That is 140 questions at target and 40 checked to offer all four titles. The text of *The Tale of
Peter Rabbit* is out of copyright, but Frederick Warne & Co holds trademarks in the name: questions
are about the original 1902 text, never a film or series of it, and text only, as every pack is.
More Potter tales are content-only additions to `store/beatrix-potter.json` later.

### 4.5 Screens and navigation

```
Home ─ Arcade ─┬─ Invaders
               ├─ Snake
               └─ Quiz ─┬─ Quiz me ───────────────► Play ─► Round end
                        ├─ Pick one ─ title list ─► Play ─► Round end
                        └─ My shelf
```

- **The Arcade menu gains a third card, Quiz** (`Icons.quiz`), after Snake and above the arcade's
  Options, in the shape `_GameCard` gives Invaders and Snake (`PLAN-phase-7-snake.md` §4.9): the
  title, a best line — the best mixed round, *Best 8 out of 10*, or *Not played yet* — and a
  *Play Quiz* button that opens the Quiz menu. It has no top-five table, because a quiz has no
  `HighScore` list, so `_GameCard`'s `scores` becomes optional and a card without one draws none.
  It has no toggles either; if §9's *harder questions* switch is ever built, it goes on this card,
  as auto-fire sits on Invaders'. The arcade-wide *Easy mode* and *Buttons on the left* below the
  cards do not touch the quiz. The card appears only when the loaded catalog offers at least one
  title, so a store build made before any store pack is ready has no quiz rather than an empty one.
  The quiz's own screens take the arcade's role colour, as the menu that opens them does.
- **The Quiz menu** is three `BigButton`s. *Quiz me* is disabled with a one-line hint — *Tick what
  you've read on your shelf* — when nothing offered is ticked, and the shelf button is then
  highlighted; a disabled button that leads nowhere would otherwise be a dead end.
- **My shelf** has a four-way switch — Books, TV, Films, Topics — built as stacked `BigButton`s, the
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
stops a child who has ticked four Dahl books and one Narnia book getting four Dahl questions in
five; rotating by title within a series spreads a round across the books. Each draw advances
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
- `private`, with **the same application id, label and signing** — the owner's decision. Both are
  one app, `net.nawt.zibo_games`, with one save. The private build reaches the family's tablets as an
  APK uploaded to the Amazon Appstore's Live App Testing track, and the store build as the public
  release; a tablet moving between the two keeps its save, because the save does not depend on the
  flavour and a ticked title the build does not carry is kept rather than dropped (§4.7).

Two consequences of one app id, both checked in PR 3 rather than assumed:

- **Version codes.** A private and a store APK built from the same commit have the same
  `versionCode` (the `+N` in `pubspec.yaml`). PR 3 reads Amazon's current rule for version codes
  across a Live App Testing upload and a live release. If they must differ, the private flavour
  sets `versionCode` to the store's plus 50,000, so a private build always outranks the store
  build of the same and every earlier release, and a tester's tablet is not offered the public
  build as an update over it. The cost is one-way: Android will not install a lower version code
  over a higher one, so a tablet leaves the testing track for the public build only by uninstalling,
  after exporting its players. The rule and the choice are recorded here.

  *Recorded in PR 3:* Amazon's Live App Testing documentation requires a test build promoted to
  live to carry a version code at least the live build's (its *Understanding Live App Testing* page
  says strictly greater), and its console warns when a test's devices are on version codes below the
  live version's. Nothing requires a test build to differ from live while it stays a test, but the
  private build is never promoted: the store build is the public release, so the first store
  release after a test build would put the live version code above the test's, which is the warned
  case and the update this rule exists to prevent. So the codes differ: the private flavour sets
  `versionCode` to the store's plus 50,000, in `build.gradle.kts`, and `android-apk.yml` fails if
  the two APKs it builds are not exactly 50,000 apart. developer.amazon.com was not reachable from
  the session that built PR 3, so the rule was read from search results quoting those pages; §8's
  device line on a real testing-track tablet is what confirms it.
- **Signing.** An app installed from the Amazon Appstore carries Amazon's signature, and an APK
  sideloaded from CI carries the repository's key. Android will not replace one with the other
  without an uninstall, which deletes the save. So a tablet changes route only after exporting its
  players to a file (`PLAN-transfer.md`); `README.md` says so beside the private build command.

Once Android has product flavours, a `flutter build apk` with no `--flavor` no longer finds a single
APK, so CI and `README.md` pass `--flavor store` and the artifact becomes `app-store-release.apk`.
Every reference to `app-release.apk` — `android-apk.yml`, the usage comments in
`check_apk_permissions.sh` and `apk_signing_cert.sh`, `README.md` — moves with it in the same pull
request. PR 3 records what an unflagged Android build does in practice; if it quietly produces a
private build rather than failing, PR 3 fixes that before merging, because the safe direction for a
forgotten flag is the store.

*Recorded in PR 3:* an unflagged `flutter build apk --release` runs Gradle's `assembleRelease`,
which builds **both** flavours, each with the right assets, because the Flutter Gradle plugin hands
each variant its own flavour when it bundles assets. The Flutter tool then looks for
`app-release.apk`, finds none, and exits 1 with *Gradle build failed to produce an .apk file*. A
temporary CI step (reverted in the same pull request) showed both packages left in `flutter-apk/`:
`app-store-release.apk` with no private entry and `app-private-release.apk` with two. So a
forgotten flag fails rather than quietly producing a private build, and nothing needed fixing. The
private package it leaves behind is named for what it is. `flutter run` and `flutter test -d` on an
Android device fail the same way without `--flavor`, which `README.md` and `AGENTS.md` now say.

iOS, macOS, Linux and Windows declare no flavours and build without `--flavor` — `flutter build
linux` and `flutter build windows` do not accept one in Flutter 3.44 — so they are always store
builds, and CI's existing legs for them change nothing. No `default-flavor` entry goes in
`pubspec.yaml`, because it would apply to iOS and macOS too and demand Xcode schemes that do not
exist (§3).

**What the app knows.** Content is decided by what is bundled, not by a flag the code reads, so
there is one mechanism rather than two that could disagree. The one runtime use of the flavour is
the settings footer, which appends *home build* when `appFlavor` (`package:flutter/services.dart`)
is `private`. With one app id and one label, the footer is the only way to tell which build a tablet
has.

**The check.** `tool/check_quiz_audience.sh <apk> store|private` lists the APK with `unzip -l`. In
`store` mode it fails on any `flutter_assets/assets/quiz/private/` entry; in `private` mode it fails
if there is none, which proves the flavour mechanism bundled them rather than letting the store check
pass vacuously. Its `--self-test` runs both modes against canned listings, per `AGENTS.md`'s rule
that a guard needs its own test. `android-apk.yml` builds both flavours and checks both; it uploads
the store APK as now, and the private APK only on a `workflow_dispatch` run that asks for it — that
artifact is what the owner uploads to Live App Testing. `android-release.yml` attaches only the store
APK to a release.

**What this does not do.** It keeps private packs out of the public release; it does not make them
secret. This repository is public, so the private packs' JSON is readable on GitHub, and an Actions
artifact on a public repository can be downloaded by any signed-in GitHub user. The owner has
accepted that: the private questions stay in this repository. If that changes, the private
directory's *source* moves — a gitignored local directory, or a private repository checked out into
it — and nothing in the app or the build changes, because the build reads a path.

---

## 5. Repository layout

```
app/assets/quiz/
  store/                          # in every build (§4.9)
    index.json                    # series in shelf order, withdrawn titles
    beatrix-potter.json, general-knowledge.json
  private/                        # only in `--flavor private` builds
    index.json
    faraway-tree.json, narnia.json, dahl.json, rainbow-magic.json, kitty.json
    cbeebies-bluey.json, cbeebies-topsy-and-tim.json, cbeebies-hey-duggee.json,
    cbeebies-waffle.json, disney.json
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
its own series' file, and two can be written in parallel without conflicting. CBeebies shows get a
file each for the same reason; Disney's three broad titles share one, because they are drafted
together and a film moving into a title of its own stays inside it (§4.4). `model/`
imports nothing from Flutter so the round logic is tested in plain `test()` and runs in milliseconds;
the loader, which needs `rootBundle`, is the only part of the catalog in `data/`.

---

## 6. Pull requests

Estimates assume one developer, or one agent session with review, working on this full time, as
phase 9's did. **Checking content is separate and is the owner's time**: verifying a question, its
answer and its three wrong answers against the book or episode takes about two to three minutes with
the source to hand, so the launch threshold of 190 checked questions is roughly 6–10 hours, plus
about half an hour per Kitty book, and the full target of 440 a little over twice that. The store packs need 40 checked questions to offer all four titles,
about two hours, and 140 at target. That is the phase's real critical path, and why the release line does
not wait for it.

| PR | Title | Estimate |
|---|---|---|
| 1 | This plan | — |
| 2 | Pack format, loader, content test, and the Faraway Tree pack | 1.5–2 days |
| 3 | Store and private builds | 1–1.5 days |
| 4 | Save field and transfer round trip | 0.5–1 day |
| 5 | The round model, and `GameRng` moved to `core/` | 1–1.5 days |
| 6 | The screens and the Quiz card | 2–3 days |
| 7 | Narnia | 0.5 day drafting |
| 8 | Roald Dahl | 1 day drafting |
| 9 | Rainbow Magic and Kitty | 1–1.5 days drafting, by the number of Kitty books |
| 10 | CBeebies | 1 day drafting |
| 11 | Disney | 1.5 days drafting |
| 12 | Store packs: Peter Rabbit and general knowledge | 1.5 days drafting |
| 13 | Smoke test, device pass and close | 0.5–1 day, plus device time |

Total 13–17 working days of building and drafting, plus checking. PR 6 is the widest because §4.8's
measurement may move the caps and the shelf is the first screen in the app that scrolls a long list.
Content pull requests 7–12 depend only on PR 2 and can be built in any order or in parallel; their
order here is the ask's, books before screens.

**PR 1 — this plan.** `PLAN-phase-10-quiz.md`, and a phase 10 entry in `PLAN.md` §7.
**Done when:** both are on `main`, with the owner's answers to placement and the launch list
recorded in §4.4, §4.5 and §9.

**PR 2 — format, loader, content test, first pack.** `QuizCatalog`, `QuizQuestion`,
`QuizCatalogLoader`, both `index.json` files, `private/faraway-tree.json` with 20 drafted questions
per book, the content test and its broken fixtures, and both directories declared in `pubspec.yaml`
as §4.9 shows — the private one flavour-tagged from its first commit, so no build ever carries it
untagged, even before PR 3 gives Android the flavour that can bundle it.
**Done when:** `flutter test test/features/quiz` passes; each content rule of §4.3 fails against its
fixture (shown in the PR description); a loader test in release mode drops an unchecked question and
hides a title with nine checked; a pack with a syntax error is skipped and the others still load;
the coverage table is in the PR description; the parse time of the bank, scaled to 1,000 questions, is
recorded in §8.
*Outcome:* built as above, with one shortfall. *The Enchanted Wood* has its 20 drafted questions, but
the other three books have 5, 2 and 4: they were drafted with no copy of the books and no reference
to hand, and questions guessing which book a land or a cousin first appears in were cut rather than
left for a checker to catch, because a wrong guess there breaks §1's spoiler rule as well as a fact.
Their titles and ids are in the pack, so the remaining questions are a content-only change, drafted
from the books in the same way PRs 7–12 are. All four are hidden until each has ten checked
questions, so nothing reaches a child in the meantime.

**PR 3 — store and private builds.** The two Android product flavours, `--flavor store` in CI and
`README.md`, the `app-store-release.apk` rename everywhere, `tool/check_quiz_audience.sh` with its
self-test, the private build and check in `android-apk.yml`, and the footer's *home build* (§4.9).
**Done when:** the store APK from CI passes `check_quiz_audience.sh store` and the private APK passes
`check_quiz_audience.sh private`; each fails the other's mode (shown in the PR description);
`--self-test` passes; `grep -rn 'app-release.apk' .github tool README.md` prints nothing; CI's
iOS, macOS, Linux and Windows legs are green with no change to their commands; the private APK's
`aapt dump badging` shows the same package name and label as the store APK's; Amazon's version-code
rule and the resulting choice are recorded in §4.9; what an unflagged
`flutter build apk` does is recorded in §4.9; a footer widget test shows *home build* for `private`
and nothing for `store` or no flavour.
*Outcome:* built as above. The audience check also requires the store index in both modes, so
neither passes on a listing that is not of a quiz-carrying APK, and its self-test includes a
20,000-entry listing: the first draft piped `printf` into `grep -q` under `pipefail`, which fails
intermittently on a real APK's listing when `grep` stops reading early, and that case fails against
it every time. The cross-mode failures and the identity comparison (package name, label, and
version codes exactly 50,000 apart) run on every CI build rather than once, so the evidence the
done-when asks for is in every Android log. The Android leg now builds twice; the second build
reuses Gradle's work and took about a minute on CI against five for the first.

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
within itself; a mixed round over one ticked Narnia book and four ticked Dahl books draws exactly
five Narnia questions out of ten, the series alternating; every level-1 question in a round precedes every level-2 one;
each question's three options are distinct and include the answer; `game_rng_test.dart` passes with
its literals unchanged; `no_random_test.dart` still passes.

**PR 6 — the screens.** The Quiz menu, shelf, title list and play screen, the Quiz card on the Arcade
menu, routes, sounds and haptics.
**Done when:** a widget test plays a ten-question round to the round-end card and sees the score
written to the save; ticking a title on one profile leaves another profile's shelf unchanged; *Quiz
me* is disabled with nothing ticked and enabled after one tick; `layout_sweep_test.dart` passes with
the four new routes; §4.8's longest-content test passes at 200 % text on 360 x 640 dp; the Arcade
menu shows the Quiz card after Snake with *Not played yet*, then the best mixed score once a round is
played, and no Quiz card over a catalog that offers nothing; the Invaders and Snake cards and their
tests are unchanged; screenshots of the shelf and a question, day and
night, are attached to the PR rather than committed. The app version moves to 0.5.1, the first build
in which a child can reach the quiz.

**PRs 7–11 — content.** Each adds its series' packs at 20 drafted questions per title — 40 per
Disney title — with `checked: false` on everything not yet verified, and pastes the coverage table.
A follow-up commit or pull request by the owner flips `checked` as questions are verified;
corrections go in the same commit as the flip.
**Done when (each):** the content test passes; every title in the pull request has its target of
questions (§4.4), at least 30 % of them at level 1; the coverage table is in the description; no
title id outside the pull request's series changed (`git diff --stat` touches only its own files and
`index.json`).

**PR 12 — store packs.** `store/beatrix-potter.json` with *The Tale of Peter Rabbit* at 20 drafted
questions, and `store/general-knowledge.json` with *Animals*, *The UK* and *The world* at 40 each,
every topic question keeping to facts that do not change (§4.2). The same done-when as PRs 7–11
(with 40 per topic in place of 20), plus a loader test over the real store directory: with every question
unchecked the store catalog offers nothing and the Arcade menu shows no Quiz card (§4.5); with ten
of one title's questions checked, it offers that title and the card appears.

**PR 13 — smoke test, device pass, close.** `app/integration_test/quiz_smoke_test.dart` drives home,
Arcade, Quiz, the shelf, a tick, *Quiz me* and a full round to the round-end card, and checks the
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
| A trademark or copyright complaint, or a store rejecting the listing | Medium | Every named series starts private and is not in a store build (§4.4, §4.9); the store gets Peter Rabbit and general knowledge unless the owner moves a pack. Peter Rabbit's name is a Frederick Warne trademark even though the 1902 text is out of copyright, so it is held to the same text-only rule. Text only, original wording, no art, logos, stills, tunes or long quotations (§1); the content test bounds text length and refuses non-JSON assets. The store listing names no series. This plan does not claim any of it is legally safe (§9). |
| A private pack ships in a store build | High | The directory is the audience and is flavour-tagged from its first commit (PR 2); only `--flavor private` bundles it; `check_quiz_audience.sh` fails CI on a private entry in the store APK and on none in the private APK, so a broken mechanism cannot pass by finding nothing; the script has a self-test. Non-Android targets declare no flavour and cannot build a private variant. |
| Private content is assumed secret and is not | Low | Accepted by the owner: the repository is public and so is its JSON (§4.9). If that changes, the private directory's source moves and nothing else does. |
| A tester's tablet is updated from the private build to the public one, and the private titles vanish | Medium | §4.9's version-code rule, settled in PR 3 against Amazon's documentation. The save survives either way — one app id, and ticks on titles the build lacks are kept (§4.7) — so the worst case is the private questions missing until the next test build. §8's device line checks it on a real testing-track tablet. |
| Switching a tablet between a sideloaded and an Amazon-installed build deletes its save | Medium | Android refuses to replace an app signed with a different key without an uninstall. `README.md` tells the owner to export players to a file first (`PLAN-transfer.md`); the transfer round trip is already tested. |
| A general-knowledge answer goes out of date | Low | Topic questions ask only for facts that do not change (§4.2), a reviewer's rule rather than a mechanism; `source` names the reference, so a reported error is rechecked quickly. |
| Adding flavours breaks an existing build or a habit | Medium | Android only; PR 3's done-when requires the other four CI legs green with unchanged commands and every `app-release.apk` reference moved; an unflagged Android build's behaviour is checked and made to fail or build the store rather than the private variant. |
| A question spoils a book the child has not read | Medium | One title per question, the latest a reader needs (§4.1); mixed rounds draw only from ticked titles (§4.6). Review is the only check on which title a question belongs to; no mechanism can judge it. |
| The text is too much for the youngest players | Medium | Three options; length caps enforced by the content test and measured in PR 6 (§4.8); level-1 questions first in every round; the screen reader reads it all. Proven only by §8's device line with a six-year-old. |
| Questions repeat so often a child is bored | Low | §4.6's per-title order asks every question before any repeat; PR 5's test proves it over three cycles. |
| A pack ships malformed and the quiz breaks on a device | Low | The content test in CI; the loader skips a bad pack and keeps the rest (PR 2's test). |
| Renaming a title id unticks it on every shelf | Medium | Ids are frozen once shipped (§3); withdrawal is the only removal (§4.1). The content test cannot know what shipped, so PR 13 adds a test pinning every title id that exists at the close: removing or renaming one then fails the build. |
| A broad Disney title spoils a film the child has not seen | Medium | Ticking *Pixar films* does not mean every Pixar film has been watched, so the per-title rule of §1 cannot protect it. §4.4's reviewer rule — a question asks only what a film's opening shows — is checked with every `checked` flip, and `source` names the film. A film a child wants asked about in depth becomes its own title. |
| Kitty is drafted against books the family does not have | Low | PR 9 takes the list from the publisher's and the owner trims it before drafting; a book left out is a content-only addition later. |
| The shelf is too long to scroll comfortably on a phone | Low | Grouped by collection behind a four-way switch, so the longest list is Books at 13 titles plus Kitty's; *I've read them all* per series. Checked in §8. |

---

## 8. Verification checklist

- [x] `cd app && flutter test test/features/quiz` passes, including the content test over the real
      bank; each content rule fails against its broken fixture. *(PR 2.)*
- [x] The loader in release mode drops every unchecked question and hides a title below ten checked
      (loader test). *(PR 2.)*
- [x] Bank parse time, scaled to 1,000 questions, recorded here: 13–19 ms on a cloud development
      container, a fifth of §4.2's 100 ms bar, so the parse stays off `compute`. `content_test.dart`
      prints the figure on every run, so the CI runner's number is in the app-test log. *(PR 2.)*
- [x] `tool/check_quiz_audience.sh store` passes on CI's store APK and fails on its private APK, the
      reverse holds in `private` mode, and `--self-test` passes. *(PR 3, and every CI run after:
      `android-apk.yml` asserts all four.)*
- [x] `grep -rn 'app-release.apk' .github tool README.md` prints nothing. *(PR 3.)*
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
- [ ] *(Device)* A tablet on the Amazon Live App Testing track installs the private build over the
      store build with its save intact; its shelf shows store and private series and its footer says
      *home build*; a tablet on the public listing shows only store series; and a later public
      release does not replace the private build on the testing tablet. The last part needs a
      published listing (`PLAN.md` §7, phase 6) and stays open until one exists.

---

## 9. Open questions

| Question | What resolves it |
|---|---|
| The game's label. "Quiz" is the working name and the route prefix; the label is not frozen. | The owner. Held in one constant, as `tracksMenuTitle` is. |
| Which series, if any, move from private to the store. All start private (§4.4). | The owner, per series, at any time: a `git mv` between the two directories, keeping title ids and every child's ticks. Advice is the owner's to seek; the plan does not claim naming a series in a store build is legally safe. |
| Which other Beatrix Potter tales, and which further topics (the sea, space, the body), join the store packs. | The owner, any time; each is a content-only change. |
| Narnia's order once *The Magician's Nephew* or *The Horse and His Boy* joins: current numbering (*The Magician's Nephew* first) or publication order. It decides which title a series-wide question belongs to (§4.1). The two launch books are in the same order either way. | The owner, before either book is drafted. |
| Which Kitty books, from Oxford University Press's list. | The owner, in PR 9. |
| *Wonka* is read as *Charlie and the Chocolate Factory* (§4.4). Is that right, and is *Charlie and the Great Glass Elevator* wanted too? | The owner, before PR 8. |
| *Topsy and Tim* began as Jean and Gareth Adamson's books. TV only, as the ask lists it, or a book series too? | The owner. TV only until told otherwise. |
| Further Narnia, Dahl and Rainbow Magic books, Disney or Pixar films as titles of their own, and *Witch Detectives*. | The owner, any time; each is a content-only change. |
| Who checks the questions, and are 10 to offer and 20 as the target the right numbers? | The owner. Both are constants. |
| Built-in read-aloud for non-readers (§2). | Deferred; the device pass shows whether the screen reader is enough. |
| A per-profile *harder questions* switch using `level` (§2). | Deferred; the device pass shows whether one level mix suits both a five- and a nine-year-old. |
| Two players taking turns (§2). | Deferred. |

**Answered by the owner:** the private build is the same app as the store build, delivered to the
family's tablets through the Amazon Appstore's Live App Testing track (§4.9); the private questions
stay in this public repository (§4.9); the store packs are Peter Rabbit and general knowledge about
the world, the UK and animals (§4.4). And, closing the planning (§4.4, §4.5):

- **Placement:** a third card on the Arcade menu, not the Puzzles menu or the home screen.
- **Kitty:** Paula Harrison's series. The plan's earlier doubt — that her Kitty is a girl with
  cat-like powers rather than a detective — is settled by the owner naming it.
- ***Witch Detectives*** is left out for now; it may be too new.
- **Roald Dahl:** *The BFG*, *Matilda*, *Wonka* — read here as *Charlie and the Chocolate Factory*
  — and *James and the Giant Peach*.
- **Disney:** general questions about Mickey and friends and about other Disney titles, Pixar's
  included — three broad titles, not a title per film or per Mickey show.
- **Rainbow Magic:** the colour fairies (*the Rainbow Fairies*) and *the Weather Fairies*, one tick
  per set.
- **Narnia:** *The Lion, the Witch and the Wardrobe* and *Prince Caspian*, for now.

---

## 10. Starting order

1. Nothing in §9 blocks a pull request: placement and the launch list are answered (§4.4, §4.5),
   and Kitty's book list is settled inside PR 9.
2. PR 2: the content test and its broken fixtures **before** the loader, so the format is enforced
   before any pack depends on it; then the Faraway Tree pack, which is the first real input.
3. PR 4 and PR 5 in either order, then PR 6. Start content drafting (PRs 7–12) as soon as PR 2 is
   merged, and start checking as soon as the first pack is drafted: checking is the critical path
   (§6), and every hour of it done before PR 13 is a title a child can play at release.
