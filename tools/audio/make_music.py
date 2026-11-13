#!/usr/bin/env python3
"""Composes and renders the game's music to looping OGG files.

    python3 tools/audio/make_music.py [track ...]

Writes assets/audio/music/{theme,battle,night,lament,lyre}.ogg. Every note is
synthesised here with numpy: string and choir pads, horn, a reed pipe
(aulos), a plucked lyre and skin drums, in a hall made by convolution. No
samples or recordings are used. Each track loops without a seam: whatever
rings past the end is folded back onto the start.

The mode is D minor leaning on the lowered second (E flat), the nearest
modern scale to the Greek Dorian.

Needs: pip install numpy scipy; ffmpeg with libvorbis.
"""

import re
import subprocess
import sys
from pathlib import Path

import numpy as np
from scipy import signal

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "audio" / "music"
SR = 32000
TAU = 2.0 * np.pi
STEP = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
rng = np.random.default_rng(1184)


def hz(name: str) -> float:
    m = re.fullmatch(r"([A-G])([b#]?)(-?\d)", name)
    semis = STEP[m[1]] + {"#": 1, "b": -1, "": 0}[m[2]] + (int(m[3]) - 4) * 12 - 9
    return 440.0 * 2.0 ** (semis / 12.0)


def lowpass(x: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
    b, a = signal.butter(order, min(fc / (SR / 2), 0.98), "low")
    return signal.lfilter(b, a, x, axis=0)


def highpass(x: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
    b, a = signal.butter(order, fc / (SR / 2), "high")
    return signal.lfilter(b, a, x, axis=0)


def peak(x: np.ndarray, f: float, q: float) -> np.ndarray:
    b, a = signal.iirpeak(f / (SR / 2), q)
    return signal.lfilter(b, a, x, axis=0)


def shape(n: int, attack: float, release: float) -> np.ndarray:
    e = np.ones(n)
    na = max(min(int(attack * SR), n // 2), 1)
    nr = max(min(int(release * SR), n - na), 1)
    e[:na] = np.sin(np.linspace(0.0, np.pi / 2, na)) ** 2
    e[n - nr:] *= np.cos(np.linspace(0.0, np.pi / 2, nr)) ** 2
    return e


def saw(freq, n: int) -> np.ndarray:
    phase = np.cumsum(np.broadcast_to(freq, (n,)) / SR) + rng.random()
    return 2.0 * (phase % 1.0) - 1.0


def stereo(left: np.ndarray, right: np.ndarray) -> np.ndarray:
    return np.stack([left, right], axis=1)


# --- instruments (each returns an (n, 2) array) -----------------------------------

def pad(freq: float, dur: float, bright: float = 1400.0, attack: float = 0.9) -> np.ndarray:
    """A section of bowed strings: six detuned saws, three to a side."""
    n = int((dur + 1.4) * SR)
    sides = []
    for _side in range(2):
        s = np.zeros(n)
        for _k in range(3):
            cents = rng.uniform(-9.0, 9.0)
            t = np.arange(n) / SR
            drift = 1.0 + 0.0015 * np.sin(TAU * rng.uniform(0.15, 0.5) * t + rng.uniform(0, TAU))
            s += saw(freq * 2.0 ** (cents / 1200.0) * drift, n)
        sides.append(lowpass(s / 3.0, bright))
    return stereo(*sides) * shape(n, attack, 1.3)[:, None]


def horn(freq: float, dur: float, bright: float = 2100.0, attack: float = 0.08) -> np.ndarray:
    """Brass: the tone opens up as the note swells."""
    n = int((dur + 0.3) * SR)
    t = np.arange(n) / SR
    vib = 1.0 + 0.0045 * np.sin(TAU * 5.1 * t) * np.clip((t - 0.4) / 0.5, 0.0, 1.0)
    s = (saw(freq * vib, n) + saw(freq * 1.003 * vib, n)) * 0.5
    e = shape(n, attack, 0.28) * (0.82 + 0.18 * np.exp(-t * 3.0))
    tone = lowpass(s, 520.0) * (1.0 - 0.75 * e) + lowpass(s, bright) * 0.75 * e
    x = tone * e
    return stereo(x, x)


def choir(freq: float, dur: float, vowel: str = "ah") -> np.ndarray:
    """Voices on a held vowel: a buzzing source through three formants."""
    formants = {"ah": (700.0, 1150.0, 2700.0), "oh": (450.0, 850.0, 2600.0), "oo": (330.0, 780.0, 2400.0)}[vowel]
    n = int((dur + 1.6) * SR)
    t = np.arange(n) / SR
    sides = []
    for _side in range(2):
        s = np.zeros(n)
        for _k in range(3):
            cents = rng.uniform(-11.0, 11.0)
            vib = 1.0 + 0.006 * np.sin(TAU * rng.uniform(4.6, 5.8) * t + rng.uniform(0, TAU))
            s += saw(freq * 2.0 ** (cents / 1200.0) * vib, n)
        v = peak(s, formants[0], 6.0) + 0.55 * peak(s, formants[1], 8.0) + 0.3 * peak(s, formants[2], 9.0)
        sides.append(lowpass(v, 4200.0) / 3.0)
    return stereo(*sides) * shape(n, 0.7, 1.4)[:, None]


def aulos(freq: float, dur: float) -> np.ndarray:
    """The double reed pipe: two pipes a hair apart, hollow and nasal."""
    n = int((dur + 0.25) * SR)
    t = np.arange(n) / SR
    vib = 1.0 + 0.007 * np.sin(TAU * 4.8 * t) * np.clip((t - 0.5) / 0.6, 0.0, 1.0)
    x = np.zeros(n)
    for pipe in (1.0, 2.0 ** (7.0 / 1200.0)):
        phase = np.cumsum(freq * pipe * vib / SR)
        for k, amp in ((1, 1.0), (2, 0.18), (3, 0.55), (4, 0.08), (5, 0.3), (7, 0.16), (9, 0.08)):
            if freq * k < SR * 0.45:
                x += amp * np.sin(TAU * k * phase)
    breath = peak(rng.standard_normal(n), min(freq * 3.0, 6000.0), 2.0) * 0.5
    x = lowpass(x * 0.25 + breath * 0.05, 3400.0) * shape(n, 0.09, 0.22)
    return stereo(x, x)


def lyre(freq: float, dur: float = 1.8) -> np.ndarray:
    """A gut string plucked: upper partials die first."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for k in range(1, 13):
        f = freq * k * (1.0 + 0.00025 * k * k)
        if f > SR * 0.45:
            break
        x += np.sin(TAU * f * t + rng.uniform(0, TAU)) * k ** -1.15 * np.exp(-t * (1.6 + 0.75 * k))
    pluck = lowpass(rng.standard_normal(n), 3000.0) * np.exp(-t * 220.0) * 0.5
    x = (x + pluck) * shape(n, 0.002, 0.12)
    return stereo(x, x)


def drum(f0: float, f1: float, rate: float, skin: float = 0.5) -> np.ndarray:
    """A skin drum: a falling tone and the slap of the hand."""
    n = int(min(7.0 / rate + 0.1, 2.2) * SR)
    t = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-t * 20.0)
    phase = np.cumsum(f / SR)
    body = (np.sin(TAU * phase) + 0.35 * np.sin(TAU * 1.59 * phase) + 0.2 * np.sin(TAU * 2.3 * phase)) * np.exp(-t * rate)
    slap = lowpass(rng.standard_normal(n), 1800.0) * np.exp(-t * 55.0) * skin
    x = (body + slap) * shape(n, 0.002, 0.05)
    return stereo(x, x)


def boom() -> np.ndarray:
    return drum(120.0, 58.0, 4.6, 1.0)


def tom(pitch: float = 1.0) -> np.ndarray:
    return drum(190.0 * pitch, 112.0 * pitch, 11.0, 0.5)


def rattle(accent: float = 1.0) -> np.ndarray:
    """A sistrum shake."""
    n = int(0.16 * SR)
    t = np.arange(n) / SR
    x = highpass(rng.standard_normal(n), 3500.0) * np.exp(-t * 42.0) * accent
    return stereo(x, x)


def swell(dur: float) -> np.ndarray:
    """A rising wash into a downbeat."""
    n = int(dur * SR)
    t = np.arange(n) / n
    left = lowpass(highpass(rng.standard_normal(n), 800.0), 7000.0)
    right = lowpass(highpass(rng.standard_normal(n), 800.0), 7000.0)
    return stereo(left, right) * (t ** 2.5 * np.exp(-((t - 1.0) ** 2) * 2.0))[:, None]


def stab(freq: float) -> np.ndarray:
    """Low strings, short bow strokes."""
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    x = lowpass(saw(freq, n) + saw(freq * 1.004, n), 1500.0) * np.exp(-t * 13.0) * shape(n, 0.006, 0.05)
    return stereo(x, x)


# --- mixing ----------------------------------------------------------------------

class Mix:
    """A stereo tape with a dry bus and a send to the hall."""

    def __init__(self, seconds: float) -> None:
        self.n = int(round(seconds * SR))
        self.margin = 12 * SR
        self.dry = np.zeros((self.n + self.margin, 2))
        self.send = np.zeros((self.n + self.margin, 2))

    def add(self, x: np.ndarray, at: float, gain: float = 1.0, pan: float = 0.0, wet: float = 0.35) -> None:
        i = int(round(at * SR)) % self.n
        x = x[: self.dry.shape[0] - i]
        g = np.array([np.cos((pan + 1.0) * np.pi / 4), np.sin((pan + 1.0) * np.pi / 4)]) * 1.4142 * gain
        self.dry[i:i + x.shape[0]] += x * g
        self.send[i:i + x.shape[0]] += x * g * wet

    def render(self, hall: float = 2.8, target_db: float = -17.0, lift: float = 1.3) -> np.ndarray:
        n_ir = int(hall * SR)
        t = np.arange(n_ir) / n_ir
        ir = rng.standard_normal((n_ir, 2)) * np.exp(-6.9 * t)[:, None]
        ir = lowpass(highpass(ir, 180.0), 5200.0)
        ir[: int(0.018 * SR)] = 0.0
        ir /= np.sqrt(np.sum(ir * ir, axis=0))
        wet = np.stack([signal.fftconvolve(self.send[:, c], ir[:, c]) for c in range(2)], axis=1)
        out = np.zeros((max(wet.shape[0], self.dry.shape[0]), 2))
        out[: self.dry.shape[0]] += self.dry
        out[: wet.shape[0]] += wet
        # Fold everything that rings past the end back onto the beginning.
        loop = out[: self.n].copy()
        rest = out[self.n:]
        while rest.shape[0] > 0:
            part = rest[: self.n]
            loop[: part.shape[0]] += part
            rest = rest[self.n:]
        # Master tone, filtered across the seam. Phone speakers give nothing
        # below 200 Hz, so the weight is pulled out of the bass and the
        # instruments that carry the tune are lifted.
        twice = highpass(np.concatenate([loop, loop]), 45.0)
        twice = twice - 0.55 * lowpass(twice, 170.0) + lift * highpass(twice, 900.0, 1)
        loop = twice[self.n:]
        loop *= 10 ** (target_db / 20.0) / np.sqrt(np.mean(loop * loop))
        return np.tanh(loop * 1.15) / 1.15


def melody(mix: Mix, voice, notes: list, at: float, beat: float, gain: float, octave: float = 1.0,
           pan: float = 0.0, wet: float = 0.5, legato: float = 0.96) -> None:
    for name, beats in notes:
        if name != "-":
            mix.add(voice(hz(name) * octave, beats * beat * legato), at, gain, pan, wet)
        at += beats * beat


# --- the pieces ------------------------------------------------------------------

DM = ("D2", ["D3", "A3", "D4", "F4"])
BB = ("Bb1", ["Bb2", "F3", "Bb3", "D4"])
F = ("F2", ["F3", "A3", "C4", "F4"])
C = ("C2", ["C3", "G3", "C4", "E4"])
GM = ("G1", ["G2", "D3", "G3", "Bb3"])
A = ("A1", ["A2", "E3", "A3", "C#4"])
EB = ("Eb2", ["Eb3", "G3", "Bb3", "Eb4"])


def theme() -> np.ndarray:
    """Menu: a slow march that gathers voices and drums in its second half."""
    beat = 60.0 / 72.0
    chords = [DM, BB, F, C, DM, BB, GM, A]
    span = 8 * beat
    mix = Mix(len(chords) * span)
    for i, (bass, notes) in enumerate(chords):
        at = i * span
        full = i >= 4
        mix.add(pad(hz(bass), span, 520.0), at, 0.34)
        mix.add(pad(hz(bass) * 2.0, span, 800.0), at, 0.22)
        for j, name in enumerate(notes):
            mix.add(pad(hz(name), span, 2300.0 if full else 1500.0), at, 0.105 if full else 0.085, (j - 1.5) * 0.3)
        if full:
            mix.add(choir(hz(notes[0]), span, "oh"), at, 0.26, -0.3, 0.6)
            mix.add(choir(hz(notes[1]), span, "oh"), at, 0.22, 0.3, 0.6)
            mix.add(choir(hz(notes[3]) * 2.0, span, "ah"), at, 0.085, 0.0, 0.7)
        arp = [notes[0], notes[1], notes[2], notes[3], notes[2], notes[1]]
        for k in range(16):
            mix.add(lyre(hz(arp[k % len(arp)]) * 2.0), at + k * beat / 2, 0.075, 0.45 if k % 2 else -0.45, 0.45)
    tune = [
        ("D4", 2), ("F4", 1), ("A4", 1), ("A4", 3), ("G4", 0.5), ("F4", 0.5),
        ("G4", 2), ("F4", 1), ("D4", 1), ("F4", 3), ("-", 1),
        ("A4", 2), ("C5", 1), ("A4", 1), ("G4", 2), ("F4", 2),
        ("E4", 2), ("G4", 1), ("C5", 1), ("C5", 2), ("Bb4", 1), ("A4", 1),
        ("D5", 2), ("C5", 1), ("A4", 1), ("A4", 3), ("F4", 1),
        ("Bb4", 2), ("A4", 1), ("G4", 1), ("F4", 3), ("D4", 1),
        ("G4", 2), ("Bb4", 1), ("D5", 1), ("D5", 2), ("C5", 1), ("Bb4", 1),
        ("A4", 2), ("C#5", 1), ("E5", 1), ("E5", 2), ("A4", 2),
    ]
    melody(mix, horn, tune, 0.0, beat, 0.30, 1.0, -0.12)
    melody(mix, horn, tune[21:], 4 * span, beat, 0.16, 0.5, 0.2)
    melody(mix, lambda f, d: choir(f, d, "ah"), tune[21:], 4 * span, beat, 0.07, 2.0, 0.1, 0.7)
    for bar in range(16):
        at = bar * 4 * beat
        if bar < 8:
            mix.add(boom(), at, 0.5, 0.0, 0.5)
            if bar % 2 == 1:
                mix.add(tom(0.8), at + 3.0 * beat, 0.22, -0.3, 0.5)
                mix.add(tom(0.8), at + 3.5 * beat, 0.3, 0.3, 0.5)
        else:
            for b, g in ((0.0, 0.85), (1.5, 0.45), (2.0, 0.7)):
                mix.add(boom(), at + b * beat, g, 0.0, 0.5)
            for b, g, p in ((3.0, 0.4, 0.9), (3.5, 0.45, 1.0), (3.75, 0.35, 1.15)):
                mix.add(tom(p), at + b * beat, g, 0.35 if p > 0.95 else -0.35, 0.5)
            for k in range(8):
                mix.add(rattle(1.0 if k % 2 == 0 else 0.55), at + k * beat / 2, 0.05, 0.5, 0.3)
    mix.add(swell(2 * beat), 4 * span - 2 * beat, 0.11, 0.0, 0.6)
    mix.add(swell(2 * beat), 8 * span - 2 * beat, 0.07, 0.0, 0.6)
    return mix.render()


def battle() -> np.ndarray:
    """Fighting: war drums, short bow strokes, brass over the top."""
    beat = 60.0 / 126.0
    chords = [DM, DM, BB, C, DM, DM, GM, A]
    span = 8 * beat
    mix = Mix(len(chords) * span)
    figure = [0, 0, 0, 2, 0, 0, 1, 0, 0, 0, 0, 2, 0, 1, 2, 1]
    for i, (bass, notes) in enumerate(chords):
        at = i * span
        full = i >= 4
        tones = [hz(bass) * 2.0, hz(notes[1]), hz(notes[2])]
        for k in range(16):
            f = tones[figure[k]]
            accent = 1.0 if k % 4 == 0 else 0.7
            mix.add(stab(f), at + k * beat / 2, 0.24 * accent, -0.25, 0.3)
            mix.add(stab(f * 2.0), at + k * beat / 2, 0.11 * accent, 0.25, 0.3)
        mix.add(horn(hz(bass) * 2.0, span * 0.5, 1100.0, 0.05), at, 0.34, -0.2, 0.4)
        mix.add(horn(hz(notes[1]), span * 0.5, 1100.0, 0.05), at, 0.22, 0.2, 0.4)
        mix.add(horn(hz(bass) * 2.0, beat * 0.9, 1500.0, 0.03), at + 4 * beat, 0.3, -0.2, 0.4)
        mix.add(horn(hz(bass) * 2.0, beat * 0.9, 1500.0, 0.03), at + 5.5 * beat, 0.3, -0.2, 0.4)
        mix.add(pad(hz(notes[0]), span, 1100.0, 0.3), at, 0.11)
        if full:
            mix.add(choir(hz(notes[0]), span, "oh"), at, 0.22, -0.3, 0.6)
            mix.add(choir(hz(notes[1]), span, "oh"), at, 0.2, 0.3, 0.6)
    tune = [
        ("D4", 1.5), ("D4", 0.5), ("F4", 1), ("A4", 1), ("A4", 2), ("G4", 1), ("F4", 1),
        ("D4", 1.5), ("D4", 0.5), ("F4", 1), ("A4", 1), ("C5", 3), ("A4", 1),
        ("Bb4", 1.5), ("Bb4", 0.5), ("A4", 1), ("G4", 1), ("G4", 2), ("D4", 2),
        ("A4", 1.5), ("A4", 0.5), ("C#5", 1), ("E5", 1), ("E5", 3), ("-", 1),
    ]
    melody(mix, lambda f, d: horn(f, d, 2600.0, 0.05), tune, 4 * span, beat, 0.30, 1.0, 0.1, 0.45, 0.9)
    melody(mix, lambda f, d: horn(f, d, 2000.0, 0.05), tune, 4 * span, beat, 0.15, 0.5, -0.1, 0.45, 0.9)
    for bar in range(16):
        at = bar * 4 * beat
        for b, g in ((0.0, 0.95), (1.5, 0.6), (2.0, 0.8), (3.0, 0.5)):
            mix.add(boom(), at + b * beat, g, 0.0, 0.4)
        for b, g, p in ((1.0, 0.35, 1.0), (2.5, 0.35, 1.15), (3.5, 0.45, 0.9)):
            mix.add(tom(p), at + b * beat, g, 0.4 if p > 0.95 else -0.4, 0.4)
        if bar % 4 == 3:
            for k in range(8):
                mix.add(tom(0.8 + 0.07 * k), at + (2.0 + k * 0.25) * beat, 0.26 + 0.035 * k, -0.6 + 0.17 * k, 0.4)
        for k in range(8):
            mix.add(rattle(1.0 if k % 2 == 0 else 0.5), at + k * beat / 2, 0.055, 0.55, 0.25)
    mix.add(swell(4 * beat), 4 * span - 4 * beat, 0.12, 0.0, 0.5)
    mix.add(swell(4 * beat), 8 * span - 4 * beat, 0.12, 0.0, 0.5)
    return mix.render(2.2, -16.0)


def night() -> np.ndarray:
    """Stealth: a drone, a slow pulse, a lyre picking at the dark."""
    beat = 1.0
    bars = 16
    mix = Mix(bars * 4 * beat)
    for i in range(4):
        at = i * 16.0
        mix.add(pad(hz("D2"), 16.0, 420.0, 3.0), at, 0.42)
        mix.add(pad(hz("A2"), 16.0, 520.0, 4.0), at, 0.2, 0.4)
        mix.add(pad(hz("D3"), 16.0, 600.0, 4.0), at, 0.13, -0.4)
    mix.add(pad(hz("Eb3"), 7.0, 700.0, 3.0), 24.0, 0.12, 0.2)
    mix.add(pad(hz("Eb3"), 7.0, 700.0, 3.0), 56.0, 0.12, -0.2)
    phrases = [
        [("D4", 1), ("Eb4", 1), ("D4", 1.5), ("A3", 1)],
        [("F4", 1.5), ("Eb4", 1.5), ("D4", 1)],
        [("A4", 1), ("G4", 1), ("F4", 1), ("Eb4", 1), ("D4", 1.5)],
        [("D4", 1), ("C4", 1.5), ("D4", 1)],
        [("A3", 1), ("D4", 1), ("F4", 1), ("Eb4", 2)],
        [("G4", 1.5), ("F4", 1), ("D4", 1)],
        [("Bb4", 1), ("A4", 1), ("F4", 1), ("G4", 1), ("Eb4", 1), ("D4", 1)],
        [("D4", 2), ("A3", 1)],
    ]
    for i, phrase in enumerate(phrases):
        melody(mix, lambda f, d: lyre(f, 2.6), phrase, i * 8.0 + 1.0, beat, 0.26, 1.0, -0.3 if i % 2 else 0.3, 0.7)
    melody(mix, aulos, [("A4", 5), ("G4", 2), ("A4", 3)], 17.0, beat, 0.12, 1.0, -0.2, 0.9)
    melody(mix, aulos, [("D5", 4), ("C5", 2), ("Bb4", 2), ("A4", 4)], 48.0, beat, 0.12, 1.0, 0.2, 0.9)
    for bar in range(bars):
        at = bar * 4.0
        mix.add(boom(), at, 0.3, 0.0, 0.6)
        mix.add(boom(), at + 0.42, 0.17, 0.0, 0.6)
    for i in range(2):
        mix.add(choir(hz("A4"), 12.0, "oo"), 34.0 + i * 0.0, 0.03, 0.5 if i else -0.5, 0.9)
    return mix.render(3.6, -20.0, 0.9)


def lament() -> np.ndarray:
    """Partings and endings: a reed pipe over a rolling lyre."""
    beat = 60.0 / 54.0
    chords = [DM, BB, F, A, GM, A]
    span = 8 * beat
    mix = Mix(len(chords) * span)
    for i, (bass, notes) in enumerate(chords):
        at = i * span
        mix.add(pad(hz(bass) * 2.0, span, 600.0, 1.5), at, 0.26)
        for j, name in enumerate(notes):
            mix.add(pad(hz(name), span, 1200.0, 1.5), at, 0.075, (j - 1.5) * 0.3)
        roll = [notes[0], notes[2], notes[3], notes[2], notes[1], notes[2], notes[3], notes[2]]
        for k in range(16):
            mix.add(lyre(hz(roll[k % 8]) * 2.0, 2.4), at + k * beat / 2, 0.15 if k % 8 == 0 else 0.1,
                    0.35 if k % 2 else -0.35, 0.55)
        if i >= 4:
            mix.add(choir(hz(notes[2]) * 2.0, span, "oo"), at, 0.05, -0.3, 0.8)
            mix.add(choir(hz(notes[3]) * 2.0, span, "oo"), at, 0.045, 0.3, 0.8)
    tune = [
        ("A4", 3), ("D5", 1), ("D5", 2), ("C5", 1), ("A4", 1),
        ("Bb4", 3), ("A4", 1), ("F4", 3), ("-", 1),
        ("A4", 3), ("C5", 1), ("C5", 2), ("A4", 2),
        ("E4", 2), ("A4", 1), ("C#5", 1), ("A4", 3), ("-", 1),
        ("Bb4", 3), ("G4", 1), ("G4", 2), ("A4", 1), ("Bb4", 1),
        ("A4", 4), ("E4", 3), ("-", 1),
    ]
    melody(mix, aulos, tune, 0.0, beat, 0.2, 1.0, 0.0, 0.8)
    return mix.render(3.4, -19.0, 0.4)


def lyre_air() -> np.ndarray:
    """Walk the City: a lyre air by daylight over a quiet drone, in the Greek
    Dorian (E F G A B C D)."""
    beat = 60.0 / 66.0
    bars = 16
    mix = Mix(bars * 4 * beat)
    span = 16 * beat
    for i in range(4):
        mix.add(pad(hz("E2"), span, 380.0, 3.0), i * span, 0.22)
        mix.add(pad(hz("B2"), span, 450.0, 3.0), i * span, 0.1, 0.3)
    phrases = [
        [("B4", 1), ("A4", 0.5), ("G4", 0.5), ("A4", 1), ("E4", 1)],
        [("G4", 1), ("A4", 0.5), ("B4", 0.5), ("C5", 1.5), ("B4", 0.5)],
        [("A4", 1), ("G4", 1), ("F4", 1), ("E4", 1)],
        [("E4", 1), ("G4", 1), ("A4", 2)],
        [("B4", 0.5), ("C5", 0.5), ("D5", 1), ("C5", 1), ("B4", 1)],
        [("A4", 1), ("B4", 0.5), ("A4", 0.5), ("G4", 2)],
        [("F4", 1), ("G4", 1), ("A4", 0.5), ("G4", 0.5), ("F4", 1)],
        [("E4", 3), ("-", 1)],
    ]
    at = 0.0
    for rep in range(2):
        for i, phrase in enumerate(phrases):
            melody(mix, lambda f, d: lyre(f, 2.4), phrase, at, beat, 0.24, 1.0, -0.25 if i % 2 else 0.2, 0.6)
            at += 4 * beat
    for k in range(bars * 2):
        mix.add(lyre(hz("E3"), 2.6), k * 2 * beat, 0.1, 0.35, 0.5)
        mix.add(lyre(hz("B3"), 2.2), k * 2 * beat + beat, 0.07, -0.35, 0.5)
    melody(mix, aulos, [("E5", 3), ("D5", 1), ("C5", 2), ("B4", 2)], 32 * beat, beat, 0.07, 1.0, 0.1, 0.9)
    return mix.render(3.0, -21.0, 0.6)


TRACKS = {"theme": theme, "battle": battle, "night": night, "lament": lament, "lyre": lyre_air}


def write_ogg(path: Path, x: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2").tobytes()
    subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
         "-c:a", "libvorbis", "-q:a", "3", "-map_metadata", "-1", "-fflags", "+bitexact",
         "-flags:a", "+bitexact", str(path)],
        input=pcm, check=True)


def main() -> None:
    for name in sys.argv[1:] or list(TRACKS):
        x = TRACKS[name]()
        write_ogg(OUT / f"{name}.ogg", x)
        rms = 20 * np.log10(np.sqrt(np.mean(x * x)))
        print(f"{name:<7} {x.shape[0] / SR:5.1f} s  rms {rms:5.1f} dB  peak {np.max(np.abs(x)):.2f}  "
              f"{(OUT / (name + '.ogg')).stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    main()
