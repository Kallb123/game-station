#!/usr/bin/env python3
"""Synthesises the app's audio motifs into `app/assets/audio/`.

    python3 tool/audio/generate_motifs.py           # write the .wav files
    python3 tool/audio/generate_motifs.py --check   # fail if they have drifted

Every sound here is built from arithmetic rather than recorded or downloaded,
which is what makes the licensing trivial: there is no third-party sample in the
tree to attribute, re-license or lose. The script is the master and the .wav
files are its committed output, the same arrangement as
`tool/icon/generate_platform_icons.py`.

It needs nothing but the standard library, and is deliberately not wired into
`tool/verify.sh` or CI, for the reason the icon script is not: the outputs are
committed, so no build depends on having a synthesiser available. `--check`
exists for anyone who wants the guard by hand — it re-renders every motif and
compares the bytes, so a hand-edited asset or a tweak to this file that was
never re-run is caught rather than assumed. Rendering is pure arithmetic with no
clock and no RNG, so the comparison is exact on any machine.

## The design rules the numbers encode

The audience is a child holding a tablet in a room with other people in it
(`AGENTS.md`), and that decides more of this file than musical taste does.

- **Nothing is a buzzer.** A wrong digit gets a soft descending pair, low-passed
  to take the edge off. Failure states are not scary, so the mistake sound is
  the quietest thing here bar the pencil ticks.
- **The set is one family in one key.** Everything is C major at A4 = 440 Hz, so
  two motifs overlapping — a placement landing under the tail of a hint — still
  sound like the same app rather than two.
- **Peaks are set per motif, not normalised flat.** A placement fires hundreds
  of times per puzzle and the fanfare once, so `place` sits 15 dB under
  `complete` on purpose. Levels are relative to each other; the absolute level
  is the device's volume knob and, later, the mixer's own gain.
- **Every motif starts and ends at zero.** A waveform cut mid-cycle clicks, and
  a click is the one artefact a small speaker reproduces perfectly. Attacks are
  raised-cosine and every voice fades out over its last few milliseconds.
"""

from __future__ import annotations

import argparse
import math
import random
import struct
import sys
import wave
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OUT_DIR = REPO / "app" / "assets" / "audio"

# 44.1 kHz mono 16-bit. Mono because these are point events rather than
# something to place in a stereo field, and 44.1 kHz because every one of the six
# target platforms resamples anything else and a fanfare with an 8 kHz harmonic
# in it is worth not resampling. The whole set is a few hundred kilobytes, so
# uncompressed .wav costs less than making the build depend on an Ogg encoder.
SAMPLE_RATE = 44100

# The last few milliseconds of every voice ramp to silence. Short enough not to
# shorten a staccato note audibly, long enough that the DAC never sees a step.
FADE_OUT = 0.006

SEMITONE_OFFSETS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

# Timbres, as the relative amplitude of each harmonic starting at the
# fundamental. Additive synthesis rather than a filtered sawtooth: with only six
# sounds to make, naming the harmonics is more legible than naming a filter.
SOFT = (1.0, 0.14, 0.04)  # near-sine, for the quiet ticks
BELL = (1.0, 0.34, 0.17, 0.08, 0.03)  # struck metal, for the happy motifs
MUTED = (1.0, 0.07)  # a sine with the corner knocked off
BRASS = (1.0, 0.78, 0.58, 0.42, 0.28, 0.18, 0.11, 0.06)  # the trumpet


def note_hz(name: str) -> float:
    """Frequency of a note written as `C6`, `F#4` or `Bb3`, at A4 = 440 Hz."""
    letter, name = name[0].upper(), name[1:]
    semitones = SEMITONE_OFFSETS[letter]
    while name and name[0] in "#b":
        semitones += 1 if name[0] == "#" else -1
        name = name[1:]
    octave = int(name)
    # MIDI 69 is A4. C4 is MIDI 60, hence the 12 * (octave + 1).
    midi = 12 * (octave + 1) + semitones
    return 440.0 * 2 ** ((midi - 69) / 12)


@dataclass(frozen=True)
class Voice:
    """One note: when it starts, what it plays, and how it opens and closes.

    `decay` is the time constant of the exponential fall after the attack, not
    the length of the note — a voice keeps sounding for `duration` and is cut by
    the fade-out, so a long note with a short decay is a struck bell and a long
    note with a long decay is a held brass note.
    """

    start: float
    duration: float
    pitch: str
    gain: float = 1.0
    timbre: tuple[float, ...] = field(default=SOFT)
    attack: float = 0.006
    decay: float = 0.18
    # Where the pitch ends up, for a glide. `None` holds the starting pitch.
    bend_to: str | None = None
    # Vibrato, in Hz and in cents of depth. The trumpet's only ornament.
    vibrato_hz: float = 0.0
    vibrato_cents: float = 0.0
    # Two oscillators this far apart, in cents, summed. A few cents thickens a
    # brass note the way one player's two lips never quite agreeing does;
    # zero renders a single oscillator.
    detune_cents: float = 0.0


def render(voices: list[Voice], length: float) -> list[float]:
    """Sums `voices` into a `length`-second buffer of floats around zero.

    A voice running past the end of the buffer is an error rather than a
    truncation: the buffer would cut it mid-cycle, past the point its own
    fade-out would have brought it to zero, and the click that produces is
    exactly what `FADE_OUT` exists to prevent. It cost one already.
    """
    out = [0.0] * int(length * SAMPLE_RATE)
    for voice in voices:
        if voice.start + voice.duration > length:
            raise ValueError(
                f"{voice.pitch} at {voice.start:.3f}s runs {voice.duration:.3f}s, "
                f"past the {length:.3f}s buffer: lengthen the buffer."
            )
        detunes = (
            (0.0,)
            if voice.detune_cents == 0
            else (-voice.detune_cents / 2, voice.detune_cents / 2)
        )
        for cents in detunes:
            _add_voice(out, voice, cents, 1.0 / len(detunes))
    return out


def _add_voice(out: list[float], voice: Voice, cents: float, share: float) -> None:
    start = int(voice.start * SAMPLE_RATE)
    samples = int(voice.duration * SAMPLE_RATE)
    base = note_hz(voice.pitch) * 2 ** (cents / 1200)
    target = note_hz(voice.bend_to) * 2 ** (cents / 1200) if voice.bend_to else base
    harmonic_sum = sum(voice.timbre)

    # The phase is integrated rather than computed from t, because a glide or a
    # vibrato changes the frequency as the note sounds: sin(2*pi*f(t)*t) sweeps
    # at twice the intended rate, and the harmonics drift out of phase with the
    # fundamental as they do it.
    phase = 0.0
    for i in range(samples):
        if start + i >= len(out):
            break
        t = i / SAMPLE_RATE
        progress = i / samples

        # Exponential in pitch, so a glide's midpoint is the musical midpoint.
        freq = base * (target / base) ** progress
        if voice.vibrato_cents:
            freq *= 2 ** (
                voice.vibrato_cents
                * math.sin(2 * math.pi * voice.vibrato_hz * t)
                / 1200
            )
        phase += 2 * math.pi * freq / SAMPLE_RATE

        wave_sample = sum(
            amplitude * math.sin(harmonic * phase)
            for harmonic, amplitude in enumerate(voice.timbre, start=1)
        )
        out[start + i] += (
            wave_sample / harmonic_sum * voice.gain * share * _envelope(voice, t)
        )


def _envelope(voice: Voice, t: float) -> float:
    return _amp_envelope(t, voice.duration, voice.attack, voice.decay)


def _amp_envelope(t: float, duration: float, attack: float, decay: float) -> float:
    """The same raised-cosine-attack, exponential-decay shape as `_envelope`,
    over raw numbers rather than a `Voice` — what the noise-based explosions
    below need, since they have no pitch or timbre for a `Voice` to carry.
    """
    if t < attack:
        # Raised cosine: it reaches full amplitude with zero slope, where a
        # linear ramp arrives at a corner that is audible as a tick.
        level = 0.5 - 0.5 * math.cos(math.pi * t / attack)
    else:
        level = math.exp(-(t - attack) / decay)
    remaining = duration - t
    if remaining < FADE_OUT:
        level *= max(0.0, remaining / FADE_OUT)
    return level


def low_pass(samples: list[float], cutoff_hz: float) -> list[float]:
    """One-pole low-pass. Softens a timbre without changing its notes."""
    alpha = 1 - math.exp(-2 * math.pi * cutoff_hz / SAMPLE_RATE)
    out, previous = [], 0.0
    for sample in samples:
        previous += alpha * (sample - previous)
        out.append(previous)
    return out


def white_noise(duration: float, seed: int) -> list[float]:
    """`duration` seconds of noise in [-1, 1], for an explosion rather than a tone.

    `random.Random` rather than the engine's own `Rng` (`packages/puzzle_engine`)
    deliberately: this script is not `lib/`, `tool/check_determinism.dart` does
    not scan it, and the outputs are committed rather than generated at build
    time, so the only property that matters is that the same seed reproduces the
    same bytes for `--check` — which the standard library's Mersenne Twister
    already guarantees.
    """
    rng = random.Random(seed)
    return [rng.uniform(-1.0, 1.0) for _ in range(round(duration * SAMPLE_RATE))]


def swept_low_pass(
    samples: list[float], start_hz: float, end_hz: float
) -> list[float]:
    """`low_pass`, but the cutoff glides from `start_hz` to `end_hz` across the
    buffer. A fixed cutoff makes an explosion sound the same throughout; a
    falling one is what `player_hit` needs to read as a sweep rather than a
    klaxon (`PLAN-phase-5.md` §4.1).
    """
    out, previous = [], 0.0
    last = max(len(samples) - 1, 1)
    for i, sample in enumerate(samples):
        cutoff = start_hz * (end_hz / start_hz) ** (i / last)
        alpha = 1 - math.exp(-2 * math.pi * cutoff / SAMPLE_RATE)
        previous += alpha * (sample - previous)
        out.append(previous)
    return out


def at_peak(samples: list[float], dbfs: float) -> list[float]:
    """Scales `samples` so their loudest point sits `dbfs` below full scale."""
    peak = max((abs(s) for s in samples), default=0.0)
    if peak == 0:
        return samples
    return [s * (10 ** (dbfs / 20)) / peak for s in samples]


def write_wav(path: Path, samples: list[float]) -> bytes:
    """Encodes `samples` as 16-bit mono PCM, writes it, and returns the bytes."""
    frames = b"".join(
        struct.pack("<h", max(-32768, min(32767, int(round(s * 32767)))))
        for s in samples
    )
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(frames)
    return frames


# --- The motifs -------------------------------------------------------------
#
# One function each, returning its finished float buffer. The comment above each
# is the intent; the numbers are the only place the sound actually lives.


def place() -> list[float]:
    """A digit going into a cell: a short, soft, neutral tick.

    Deliberately says nothing about whether the digit is right. A profile set to
    `MistakeFeedback.atCompletion` hides wrongness until the grid is full, and a
    sound that brightened for a correct digit would hand that back — the child
    would learn the tick, not the Sudoku. `correct` is for the profiles that
    flag mistakes immediately; this is what the other mode plays.
    """
    return at_peak(render([Voice(0.0, 0.10, "A5", timbre=SOFT, decay=0.03)], 0.11), -18)


def correct() -> list[float]:
    """A right digit, on a profile that flags mistakes immediately: two notes up.

    A perfect fourth, E6 to A6, the second overlapping the first's tail so the
    pair reads as one gesture rather than two ticks.
    """
    return at_peak(
        render(
            [
                Voice(0.000, 0.10, "E6", timbre=BELL, decay=0.05),
                Voice(0.075, 0.20, "A6", timbre=BELL, decay=0.09, gain=0.9),
            ],
            0.29,
        ),
        -10,
    )


def wrong() -> list[float]:
    """A wrong digit: a soft descending pair, and no more than that.

    Two notes down a minor third, near-sine, low-passed at 1.4 kHz and the
    quietest motif in the set bar the pencil ticks. It has to be noticeable
    without being a telling-off — no dissonance, no buzz, no sharp attack.
    """
    voices = [
        Voice(0.000, 0.13, "A4", timbre=MUTED, attack=0.012, decay=0.07),
        Voice(0.110, 0.22, "F4", timbre=MUTED, attack=0.012, decay=0.10, gain=0.85),
    ]
    return at_peak(low_pass(render(voices, 0.34), 1400), -16)


def erase() -> list[float]:
    """Clearing a cell: the placement tick, falling instead of flat.

    A short downward glide, quieter than `place`. Undoing is not an achievement
    and not a mistake; it should be audible only as confirmation that the tap
    landed.
    """
    voices = [
        Voice(0.0, 0.12, "E5", bend_to="B4", timbre=SOFT, decay=0.05, attack=0.008)
    ]
    return at_peak(render(voices, 0.13), -20)


def hint() -> list[float]:
    """A hint arriving: three bell notes up a C major triad.

    Sparkle rather than reward — a hint costs the clean-win star (`PLAN.md`
    §3.7), so it should sound helpful and not congratulatory. The long decays
    overlap into a chord by the third note.
    """
    voices = [
        Voice(0.00, 0.34, "C6", timbre=BELL, decay=0.13, gain=0.75),
        Voice(0.07, 0.32, "E6", timbre=BELL, decay=0.13, gain=0.75),
        Voice(0.14, 0.38, "G6", timbre=BELL, decay=0.16, gain=0.8),
    ]
    return at_peak(render(voices, 0.55), -12)


def complete() -> list[float]:
    """A finished puzzle: a trumpet fanfare.

    Three G5 pickups and a held C6 over a C major triad, the shape a fanfare has
    had since before anyone thought to put one in a game. Brass comes from eight
    harmonics, a 12 ms attack, seven cents of detune between two oscillators, and
    vibrato only on the held note, which is where a player's would arrive too.
    Low-passed at 5.5 kHz: the eighth harmonic of C6 is above 8 kHz, and a small
    tablet speaker turns that into fizz.

    The loudest motif in the set, and the only one that ever plays over the
    completion card's confetti.
    """
    pickup = dict(timbre=BRASS, attack=0.012, decay=0.5, detune_cents=7.0)
    voices = [
        Voice(0.00, 0.13, "G5", gain=0.85, **pickup),
        Voice(0.15, 0.13, "G5", gain=0.9, **pickup),
        Voice(0.30, 0.13, "G5", gain=0.95, **pickup),
        # The held note, with the triad under it at lower gain so the melody
        # stays the top line rather than becoming the middle of a chord.
        Voice(
            0.45,
            0.85,
            "C6",
            gain=1.0,
            timbre=BRASS,
            attack=0.014,
            decay=1.1,
            detune_cents=7.0,
            vibrato_hz=5.5,
            vibrato_cents=9.0,
        ),
        Voice(0.45, 0.80, "E5", gain=0.42, timbre=BRASS, attack=0.02, decay=1.0,
              detune_cents=5.0),
        Voice(0.45, 0.80, "G4", gain=0.5, timbre=BRASS, attack=0.02, decay=1.0,
              detune_cents=5.0),
    ]
    return at_peak(low_pass(render(voices, 1.35), 5500), -3)


# --- The arcade set (`PLAN-phase-5.md` §4.1) --------------------------------
#
# The two shot sounds are exact mirrors of each other — one rises, one falls —
# so they are told apart by ear rather than by level alone. The three
# explosions share one enveloped-noise helper and differ only in their filter.


def _noise_burst(
    duration: float, seed: int, attack: float, decay: float
) -> list[float]:
    """`duration` seconds of enveloped white noise: the shared raw material
    under `player_hit`, `alien_hit` and `ufo_hit`, before each one's own
    filter turns it into a distinct explosion.
    """
    noise = white_noise(duration, seed)
    return [
        sample * _amp_envelope(i / SAMPLE_RATE, duration, attack, decay)
        for i, sample in enumerate(noise)
    ]


def player_shoot() -> list[float]:
    """The ship fires: a quick upward chirp.

    Rises where `alien_shoot` falls (§4.1) — the same interval and the same
    timbre, reversed, so the two are told apart by ear rather than by level
    alone.
    """
    voices = [
        Voice(0.0, 0.08, "A5", bend_to="D6", timbre=SOFT, attack=0.002, decay=0.05)
    ]
    return at_peak(render(voices, 0.09), -16)


def player_hit() -> list[float]:
    """The ship is destroyed: a descending noise sweep, not a klaxon.

    The loudest motif in the arcade set, and still not scary (`AGENTS.md`):
    the weight is in the shape, filtered noise whose brightness falls across
    the whole 500 ms, rather than in a tone with an edge to it.
    """
    burst = _noise_burst(0.5, seed=1, attack=0.004, decay=0.16)
    return at_peak(swept_low_pass(burst, 4000, 250), -8)


def alien_shoot() -> list[float]:
    """An alien fires: `player_shoot`'s chirp falling instead of rising, and
    2 dB quieter. The sound a child must react to — a shot on its way in — is
    not allowed to be confusable with the one they just fired themselves.
    """
    voices = [
        Voice(0.0, 0.10, "D6", bend_to="A5", timbre=SOFT, attack=0.002, decay=0.06)
    ]
    return at_peak(render(voices, 0.11), -18)


def alien_hit() -> list[float]:
    """An alien is destroyed: a short, dull pop — the smallest of the three
    explosions, since it is also the one heard most often.
    """
    burst = _noise_burst(0.18, seed=2, attack=0.002, decay=0.05)
    return at_peak(low_pass(burst, 1800), -12)


def alien_move() -> list[float]:
    """One step of the alien block: a single low, muted tick, not a pitched
    sequence. Cycling four descending notes on every step was drafted and cut
    — that is music by another name (`PLAN-phase-5.md` §3.4) — so this is one
    note, low enough to sit under the shots and short enough that the fastest
    wave's eleven-a-second rate does not run it into itself.
    """
    voices = [Voice(0.0, 0.055, "C3", timbre=MUTED, attack=0.002, decay=0.02)]
    return at_peak(render(voices, 0.07), -16)


def ufo_loop() -> list[float]:
    """The special enemy, while it is on screen: a wavering tone built to
    loop. Vibrato plus two oscillators 15 cents apart give the "not quite one
    pitch" warble, and a decay long enough to barely fall across its own
    length keeps a retrigger (`minisound`'s only way to loop,
    `PLAN-phase-5.md` §3.1) from reading as a pump.
    """
    voices = [
        Voice(0.0, 0.39, "F4", timbre=MUTED, attack=0.006, decay=2.0,
              vibrato_hz=6.0, vibrato_cents=60.0, detune_cents=15.0),
    ]
    return at_peak(render(voices, 0.40), -20)


def ufo_hit() -> list[float]:
    """The special enemy is destroyed: a bigger, brighter pop than
    `alien_hit` — a wider sweep and a longer tail, so the enemy that took
    several shots to line up sounds like it was worth them.
    """
    burst = _noise_burst(0.35, seed=3, attack=0.003, decay=0.12)
    return at_peak(swept_low_pass(burst, 3000, 400), -8)


def wave_clear() -> list[float]:
    """The last alien of a wave dies: a rising bell arpeggio up to a held
    note — the only progress marker Invaders has, so it is allowed to be the
    biggest bell sound in the set bar `sudoku/complete.wav` itself.
    """
    voices = [
        Voice(0.00, 0.18, "C6", timbre=BELL, decay=0.15, gain=0.8),
        Voice(0.09, 0.20, "E6", timbre=BELL, decay=0.16, gain=0.85),
        Voice(0.18, 0.22, "G6", timbre=BELL, decay=0.18, gain=0.9),
        Voice(0.27, 0.40, "C7", timbre=BELL, decay=0.30, gain=1.0),
    ]
    return at_peak(render(voices, 0.70), -8)


def extra_life() -> list[float]:
    """The 10,000-point bonus life: an octave leap with a shimmer on top,
    shaped differently from `wave_clear`'s rising triad on purpose — a bonus
    arriving mid-wave must not be mistaken for the wave ending.
    """
    voices = [
        Voice(0.00, 0.14, "C6", timbre=BELL, decay=0.10, gain=0.8),
        Voice(0.07, 0.16, "C7", timbre=BELL, decay=0.12, gain=0.9),
        Voice(0.16, 0.42, "E7", timbre=BELL, decay=0.28, gain=1.0,
              vibrato_hz=6.0, vibrato_cents=15.0),
    ]
    return at_peak(render(voices, 0.60), -8)


# --- The snake set (`PLAN-phase-7-snake.md` §4.10) --------------------------


def eat() -> list[float]:
    """The next number is eaten: a short rising blip.

    The sound heard most often in this game, the same role `sudoku/place.wav`
    plays for Sudoku: bright and quick, confirming rather than congratulating,
    because a level is ten of these (`PLAN-phase-7-snake.md` §4.10).
    """
    voices = [
        Voice(0.0, 0.09, "C5", bend_to="G5", timbre=SOFT, attack=0.004, decay=0.05)
    ]
    return at_peak(render(voices, 0.10), -14)


def not_yet() -> list[float]:
    """The snake crosses a target that is not next: soft and low.

    Deliberately not a buzzer — nothing went wrong (`PLAN-phase-7-snake.md`
    §1). One muted note, low-passed, the quietest motif in this set: a decoy
    is scenery, and the sound has to say so without a child mistaking it for
    a mistake.
    """
    voices = [Voice(0.0, 0.10, "D4", timbre=MUTED, attack=0.01, decay=0.05)]
    return at_peak(low_pass(render(voices, 0.11), 900), -22)


def crash() -> list[float]:
    """A life is lost: a short, soft thud, not a klaxon.

    The same shape as `arcade/player_hit.wav` — filtered noise sweeping down
    — scaled back for it: score, level and the counting position all survive
    a crash (`PLAN-phase-7-snake.md` §4.1), so the sound should read as a
    stumble, not a punishment.
    """
    burst = _noise_burst(0.28, seed=4, attack=0.004, decay=0.09)
    return at_peak(swept_low_pass(burst, 2200, 200), -12)


def level_clear() -> list[float]:
    """A decade is finished: a rising bell arpeggio.

    The same family as `arcade/wave_clear.wav` — the only other "a chunk of
    the game is done" sound in the app — one note shorter, because a level
    here is ten targets where a wave there can be dozens of aliens.
    """
    voices = [
        Voice(0.00, 0.16, "E6", timbre=BELL, decay=0.13, gain=0.8),
        Voice(0.08, 0.18, "G6", timbre=BELL, decay=0.15, gain=0.85),
        Voice(0.16, 0.32, "C7", timbre=BELL, decay=0.24, gain=1.0),
    ]
    return at_peak(render(voices, 0.55), -9)


MOTIFS = {
    "sudoku/place": place,
    "sudoku/correct": correct,
    "sudoku/wrong": wrong,
    "sudoku/erase": erase,
    "sudoku/hint": hint,
    "sudoku/complete": complete,
    "arcade/player_shoot": player_shoot,
    "arcade/player_hit": player_hit,
    "arcade/alien_shoot": alien_shoot,
    "arcade/alien_hit": alien_hit,
    "arcade/alien_move": alien_move,
    "arcade/ufo_loop": ufo_loop,
    "arcade/ufo_hit": ufo_hit,
    "arcade/wave_clear": wave_clear,
    "arcade/extra_life": extra_life,
    "snake/eat": eat,
    "snake/not_yet": not_yet,
    "snake/crash": crash,
    "snake/level_clear": level_clear,
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--check",
        action="store_true",
        help="re-render and compare with the committed files instead of writing",
    )
    args = parser.parse_args()

    print(f"{'motif':<22}{'length':>9}{'peak':>9}{'rms':>9}{'size':>10}")
    drifted = []
    for name, motif in MOTIFS.items():
        samples = motif()
        path = OUT_DIR / f"{name}.wav"
        path.parent.mkdir(parents=True, exist_ok=True)

        if args.check:
            existing = path.read_bytes() if path.exists() else b""
            # Re-render beside the committed file, then put the committed one
            # back: --check must not be a write with extra steps.
            temp = path.with_suffix(".wav.check")
            rendered = write_wav(temp, samples)
            temp.unlink()
            if existing[44:] != rendered or not existing:
                drifted.append(name)
        else:
            write_wav(path, samples)

        peak = max((abs(s) for s in samples), default=0.0)
        rms = math.sqrt(sum(s * s for s in samples) / len(samples))
        print(
            f"{name:<22}"
            f"{len(samples) / SAMPLE_RATE:>8.2f}s"
            f"{_dbfs(peak):>8.1f}dB"
            f"{_dbfs(rms):>8.1f}dB"
            f"{len(samples) * 2 / 1024:>9.1f}kB"
        )

    if args.check:
        if drifted:
            print(
                "\nThese no longer match this script: "
                + ", ".join(drifted)
                + "\nRe-run without --check, listen to the result, and commit it.",
                file=sys.stderr,
            )
            return 1
        print(f"\nAll {len(MOTIFS)} motifs match this script.")
    return 0


def _dbfs(level: float) -> float:
    return -math.inf if level <= 0 else 20 * math.log10(level)


if __name__ == "__main__":
    sys.exit(main())
