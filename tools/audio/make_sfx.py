#!/usr/bin/env python3
"""Renders every sound effect and ambience loop of the game to OGG files.

    python3 tools/audio/make_sfx.py [--model DIR] [name ...]

Writes assets/audio/sfx/<name>_<n>.ogg (one file per variant; the game
picks among them so that no two blows sound alike), assets/audio/ambience/
<name>.ogg (seamless loops) and assets/audio/sfx/index.json, which tells the
game how many variants each effect has.

Everything is synthesised here with numpy, except the human cries, shouts
and the talk of the feast, which are spoken by the Kokoro text-to-speech
model (as for the dialogue, see make_voices.py) and then roughened. Nothing
is a recording. A run is deterministic: the same code writes the same files.

Needs: pip install numpy scipy kokoro-onnx; ffmpeg with libvorbis; the
Kokoro model files (kokoro-v1.0.onnx, voices-v1.0.bin) in --model.
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from scipy import signal

ROOT = Path(__file__).resolve().parents[2]
SFX_OUT = ROOT / "assets" / "audio" / "sfx"
AMB_OUT = ROOT / "assets" / "audio" / "ambience"
SR = 44100
TAU = 2.0 * np.pi

rng = np.random.default_rng(0)
_kokoro = None
_model_dir = Path("/opt/kokoro")


# --- building blocks ---------------------------------------------------------------

def n_(sec: float) -> int:
    return max(int(round(sec * SR)), 1)


def t_(n: int) -> np.ndarray:
    return np.arange(n) / SR


def noise(n: int) -> np.ndarray:
    return rng.standard_normal(n)


def drift(n: int, hz: float) -> np.ndarray:
    """Slow random wandering with unit spread: gusts, the surge of a crowd."""
    g = lp(noise(n + n_(4.0 / hz)), hz, 1)[n_(4.0 / hz):]
    return g / max(g.std(), 1e-9)


def pad(x: np.ndarray, n: int) -> np.ndarray:
    out = np.zeros(n)
    out[: min(n, x.size)] = x[:n]
    return out


def place(dst: np.ndarray, src: np.ndarray, at: float, gain: float = 1.0) -> None:
    i = n_(at) if at > 0 else 0
    if i >= dst.shape[0]:
        return
    m = min(src.shape[0], dst.shape[0] - i)
    dst[i:i + m] += src[:m] * gain


def env(n: int, attack: float, decay: float) -> np.ndarray:
    t = t_(n)
    rise = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    return rise * np.exp(-np.maximum(t - attack, 0.0) / decay)


def swell(n: int, peak: float, sharp: float = 3.0) -> np.ndarray:
    """Rises to a peak at fraction [peak] of its length, then falls."""
    k = np.linspace(0.0, 1.0, n)
    up = (k / peak) ** sharp
    down = ((1.0 - k) / (1.0 - peak)) ** (sharp * 0.6)
    return np.where(k < peak, up, down)


def lp(x: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
    sos = signal.butter(order, min(fc, SR * 0.45), "low", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0)


def hp(x: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
    sos = signal.butter(order, fc, "high", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0)


def bp(x: np.ndarray, lo: float, hi: float, order: int = 2) -> np.ndarray:
    sos = signal.butter(order, [lo, min(hi, SR * 0.45)], "band", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0)


def peak_eq(x: np.ndarray, f: float, q: float, gain: float) -> np.ndarray:
    b, a = signal.iirpeak(f, q, fs=SR)
    return x + (gain - 1.0) * signal.lfilter(b, a, x, axis=0)


def sweep(x: np.ndarray, freqs: np.ndarray, q: float) -> np.ndarray:
    """A resonant band-pass whose centre follows [freqs] (one value per sample)."""
    out = np.zeros_like(x)
    zi = np.zeros(2)
    block = 96
    for i in range(0, x.size, block):
        f = float(np.clip(freqs[min(i + block // 2, x.size - 1)], 40.0, SR * 0.44))
        b, a = signal.iirpeak(f, q, fs=SR)
        out[i:i + block], zi = signal.lfilter(b, a, x[i:i + block], zi=zi)
    return out


def thump(dur: float, f0: float, f1: float, drop: float, decay: float) -> np.ndarray:
    """A body blow or a fall: a sine that sags in pitch as it dies."""
    n = n_(dur)
    t = t_(n)
    f = f1 + (f0 - f1) * np.exp(-t / drop)
    return np.sin(TAU * np.cumsum(f) / SR) * np.exp(-t / decay) * env(n, 0.0015, 10.0)


def punch(dur: float, f0: float, f1: float, drop: float, decay: float, drive: float = 3.0) -> np.ndarray:
    """A thump driven hard, so that its overtones carry the blow on a phone
    speaker that cannot play the fundamental itself."""
    x = thump(dur, f0, f1, drop, decay)
    return np.tanh(drive * x) / np.tanh(drive)


def modes(dur: float, freqs, amps, decays, beat: float = 0.0) -> np.ndarray:
    """Struck resonances. [beat] splits each into two close partials, as in
    real metal, so the ring shimmers instead of sitting still."""
    n = n_(dur)
    t = t_(n)
    out = np.zeros(n)
    for f, a, d in zip(freqs, amps, decays):
        if f >= SR * 0.45:
            continue
        ph = rng.uniform(0.0, TAU)
        if beat > 0.0:
            out += a * 0.5 * np.sin(TAU * f * (1.0 - beat) * t + ph) * np.exp(-t / d)
            out += a * 0.5 * np.sin(TAU * f * (1.0 + beat) * t + ph * 1.7) * np.exp(-t / (d * 0.85))
        else:
            out += a * np.sin(TAU * f * t + ph) * np.exp(-t / d)
    return out


# Partial ratios of a struck bronze shell (helmet, shield boss, spear socket).
BRONZE = [1.0, 1.53, 2.31, 2.72, 3.47, 4.05, 4.86, 5.62, 6.71]


def bronze(dur: float, base: float, decay: float, bright: float = 1.0) -> np.ndarray:
    freqs = [base * r * rng.uniform(0.985, 1.015) for r in BRONZE]
    amps = [(1.0 / (1.0 + i * 0.55)) * (bright ** i) for i in range(len(BRONZE))]
    decays = [decay * (1.0 / (1.0 + i * 0.35)) * rng.uniform(0.75, 1.15) for i in range(len(BRONZE))]
    return modes(dur, freqs, amps, decays, beat=0.0025)


def click(dur: float, lo: float, hi: float, decay: float) -> np.ndarray:
    n = n_(dur)
    return bp(noise(n), lo, hi) * env(n, 0.0004, decay)


def crackle(dur: float, rate: float, lo: float, hi: float, shape: np.ndarray = None) -> np.ndarray:
    """Sparse grains: gravel, tearing cloth, fire."""
    n = n_(dur)
    x = np.zeros(n)
    hits = rng.random(n) < rate / SR
    x[hits] = rng.standard_normal(hits.sum()) * rng.uniform(0.3, 1.0, hits.sum())
    x = bp(x, lo, hi)
    if shape is not None:
        x *= pad(shape, n)
    return x


def room(x: np.ndarray, seconds: float = 0.28, wet: float = 0.1, bright: float = 5000.0) -> np.ndarray:
    """A small space around a dry sound, so it does not sit in a vacuum."""
    m = n_(seconds)
    ir = rng.standard_normal(m) * np.exp(-6.9 * np.arange(m) / m)
    ir = lp(ir, bright)
    ir[: n_(0.006)] = 0.0
    ir /= np.sqrt(np.sum(ir * ir))
    tail = signal.fftconvolve(x, ir)
    out = np.zeros(tail.size)
    out[: x.size] = x
    return out + tail * wet


def finish(x: np.ndarray, level_db: float = -1.0, tail: float = 0.012) -> np.ndarray:
    """Clear the rumble no speaker plays, peak-normalise, trim silence at the
    end, and fade the last moment."""
    x = hp(x, 95.0)
    loud = np.flatnonzero(np.abs(x) > np.abs(x).max() * 0.002)
    if loud.size:
        x = x[: loud[-1] + 1]
    x = x / max(np.abs(x).max(), 1e-9) * 10 ** (level_db / 20.0)
    f = min(n_(tail), x.size // 4)
    x[-f:] *= np.linspace(1.0, 0.0, f)
    f = min(n_(0.0008), x.size // 4)
    x[:f] *= np.linspace(0.0, 1.0, f)
    return x


# --- combat ------------------------------------------------------------------------

def whoosh_thrust() -> np.ndarray:
    """A spear driven forward: short, low, the ash shaft hums through the air."""
    d = rng.uniform(0.22, 0.3)
    n = n_(d)
    k = np.linspace(0.0, 1.0, n)
    path = 380.0 + 1100.0 * np.sin(np.pi * k) ** 1.5 * rng.uniform(0.8, 1.2)
    air = sweep(noise(n), path, 2.2) * swell(n, rng.uniform(0.5, 0.65), 2.4)
    hum = bp(noise(n), 90.0, 220.0) * swell(n, 0.55, 3.0) * 0.6
    return finish(air + hum, -3.0)


def whoosh_slash() -> np.ndarray:
    """A sword cut: a bright swish with the whistle of the blade's edge."""
    d = rng.uniform(0.26, 0.34)
    n = n_(d)
    k = np.linspace(0.0, 1.0, n)
    top = rng.uniform(3200.0, 4400.0)
    path = 900.0 + (top - 900.0) * np.sin(np.pi * np.clip(k * 1.1, 0, 1)) ** 2
    air = sweep(noise(n), path, 3.0) * swell(n, rng.uniform(0.45, 0.6), 2.8)
    edge = sweep(noise(n), path * 0.92, 28.0) * swell(n, 0.55, 4.0) * 0.5
    return finish(air + edge, -3.0)


def whoosh_throw() -> np.ndarray:
    """A thrown spear going away: falling pitch and the flex of the shaft."""
    d = rng.uniform(0.6, 0.75)
    n = n_(d)
    t = t_(n)
    k = np.linspace(0.0, 1.0, n)
    path = 1900.0 * (1.0 - k) ** 1.3 + 420.0
    flex = 1.0 + 0.35 * np.sin(TAU * rng.uniform(11.0, 16.0) * t)
    x = sweep(noise(n), path, 2.6) * swell(n, 0.22, 2.0) * flex
    return finish(x, -3.0)


def wet(dur: float, start_hz: float, end_hz: float, decay: float) -> np.ndarray:
    """The squelch of a wound: a resonance that sinks while it gurgles."""
    n = n_(dur)
    t = t_(n)
    k = np.linspace(0.0, 1.0, n)
    path = end_hz + (start_hz - end_hz) * (1.0 - k) ** 2
    path = path * (1.0 + 0.18 * np.sin(TAU * rng.uniform(25.0, 45.0) * t + rng.uniform(0, TAU)))
    return sweep(noise(n), path, 7.0) * env(n, 0.004, decay)


def hit_pierce() -> np.ndarray:
    """A spear point going in: a punch to the body, a crack and a wet tail."""
    n = n_(0.5)
    x = np.zeros(n)
    place(x, punch(0.3, rng.uniform(190, 220), rng.uniform(105, 120), 0.025, 0.06), 0.0, 0.5)
    place(x, click(0.15, 280.0, 1300.0, 0.04), 0.0, 1.6)
    place(x, click(0.06, 1500.0, 6000.0, 0.012), 0.003, 1.0)
    place(x, wet(0.32, rng.uniform(1100, 1500), rng.uniform(300, 420), 0.09), 0.012, 0.8)
    if rng.random() < 0.5:
        # Through a linen corslet: a short tearing crunch.
        place(x, crackle(0.06, 2500.0, 2000.0, 6500.0, env(n_(0.06), 0.002, 0.02)), 0.004, 0.9)
    return finish(room(x, 0.25, 0.07), -1.0)


def hit_cut() -> np.ndarray:
    """A bronze blade biting: a sharp slap, the bite, then spatter."""
    n = n_(0.55)
    x = np.zeros(n)
    place(x, click(0.03, 2000.0, 9000.0, 0.006), 0.0, 1.0)
    place(x, click(0.08, 900.0, 3200.0, 0.022), 0.002, 0.9)
    place(x, modes(0.08, [3100 * rng.uniform(0.9, 1.1), 4700 * rng.uniform(0.9, 1.1), 6300.0], [0.25, 0.18, 0.1],
                   [0.02, 0.015, 0.01]), 0.0, 0.6)
    place(x, punch(0.25, rng.uniform(210, 250), rng.uniform(115, 130), 0.02, 0.045), 0.0, 0.42)
    place(x, wet(0.2, 1600.0, 500.0, 0.05), 0.01, 0.55)
    for _ in range(rng.integers(3, 7)):
        place(x, click(0.03, 1200.0, 4500.0, 0.004), rng.uniform(0.06, 0.28), rng.uniform(0.1, 0.25))
    return finish(room(x, 0.25, 0.07), -1.0)


def hit_head() -> np.ndarray:
    """A blow on the helmet: bronze rings out, or the boar's tusks clack."""
    n = n_(0.8)
    x = np.zeros(n)
    if rng.random() < 0.6:
        place(x, bronze(0.8, rng.uniform(950, 1350), rng.uniform(0.18, 0.32), 0.85), 0.0, 0.7)
    else:
        place(x, modes(0.2, [rng.uniform(850, 1000), rng.uniform(1600, 1900), rng.uniform(2700, 3100)],
                       [1.0, 0.6, 0.3], [0.03, 0.02, 0.012]), 0.0, 0.8)
    place(x, click(0.03, 1500.0, 7000.0, 0.005), 0.0, 1.0)
    place(x, punch(0.2, 210.0, 120.0, 0.02, 0.04), 0.0, 0.42)
    return finish(room(x, 0.3, 0.08), -1.5)


def block() -> np.ndarray:
    """A blow taken on the shield: ox-hide over a wicker frame booms like a
    drum, the frame cracks, and the bronze boss or rim may ring."""
    n = n_(0.9)
    x = np.zeros(n)
    f0 = rng.uniform(150.0, 195.0)
    place(x, modes(0.4, [f0, f0 * 1.59, f0 * 2.14, f0 * 2.65, f0 * 3.16], [1.0, 0.7, 0.5, 0.35, 0.2],
                   [0.12, 0.09, 0.07, 0.05, 0.04]), 0.0, 1.0)
    place(x, punch(0.2, 180.0, 110.0, 0.02, 0.04), 0.0, 0.42)
    place(x, click(0.03, 300.0, 8000.0, 0.003), 0.0, 1.6)
    place(x, click(0.08, 600.0, 2400.0, 0.02), 0.001, 1.4)
    if rng.random() < 0.6:
        place(x, bronze(0.9, rng.uniform(780, 1150), rng.uniform(0.25, 0.5), 0.75), 0.0, 0.45)
    for _ in range(rng.integers(1, 4)):
        place(x, click(0.03, 1500.0, 6000.0, 0.004), rng.uniform(0.04, 0.14), rng.uniform(0.08, 0.2))
    return finish(room(x, 0.3, 0.09), -1.0)


def clang() -> np.ndarray:
    """Bronze striking stone: a bright ping, grit, the knock of the stone."""
    n = n_(1.1)
    x = np.zeros(n)
    place(x, bronze(1.1, rng.uniform(1400, 2100), rng.uniform(0.14, 0.26), 0.9), 0.0, 0.7)
    place(x, click(0.03, 1500.0, 4500.0, 0.008), 0.0, 1.0)
    place(x, crackle(0.1, 3000.0, 3000.0, 9000.0, env(n_(0.1), 0.003, 0.03)), 0.002, 0.5)
    return finish(room(x, 0.35, 0.1), -2.0)


def stab() -> np.ndarray:
    """A dagger in the dark: close, muffled, wet. Quieter than a battle wound."""
    n = n_(0.55)
    x = np.zeros(n)
    place(x, punch(0.25, 170.0, 100.0, 0.03, 0.045), 0.0, 0.45)
    place(x, click(0.08, 300.0, 1300.0, 0.03), 0.0, 1.2)
    place(x, wet(0.45, 900.0, 260.0, 0.14), 0.01, 1.2)
    place(x, crackle(0.08, 1800.0, 1500.0, 4500.0, env(n_(0.08), 0.004, 0.03)), 0.005, 0.8)
    return finish(lp(room(x, 0.2, 0.05), 3800.0), -2.0)


def fall() -> np.ndarray:
    """A man going down in armour: knees, then the body, then his gear."""
    n = n_(1.2)
    x = np.zeros(n)
    second = rng.uniform(0.1, 0.2)
    for at, g in ((0.0, 0.6), (second, 1.0)):
        place(x, punch(0.4, rng.uniform(150, 175), rng.uniform(85, 95), 0.035, 0.08), at, g * 0.5)
        place(x, bp(noise(n_(0.15)), 250.0, 2500.0) * env(n_(0.15), 0.003, 0.05), at, g * 1.1)
    for _ in range(rng.integers(4, 9)):
        at = second + rng.uniform(0.0, 0.5) ** 1.6
        if rng.random() < 0.5:
            place(x, bronze(0.3, rng.uniform(1600, 2600), 0.06, 0.7), at, rng.uniform(0.08, 0.2))
        else:
            place(x, modes(0.1, [rng.uniform(380, 450), rng.uniform(900, 1050), rng.uniform(1600, 1900)],
                           [1.0, 0.5, 0.25], [0.025, 0.018, 0.01]), at, rng.uniform(0.15, 0.35))
    return finish(room(x, 0.3, 0.07), -2.0)


def spear_stick() -> np.ndarray:
    """A spear landing point-first: a thunk, then the shaft quivers."""
    n = n_(0.9)
    t = t_(n)
    x = np.zeros(n)
    place(x, punch(0.2, 200.0, 120.0, 0.02, 0.03), 0.0, 0.45)
    place(x, click(0.06, 250.0, 1400.0, 0.025), 0.0, 1.5)
    f = rng.uniform(26.0, 38.0)
    quiver = (np.sin(TAU * f * t) * 0.5 + 0.5) * np.exp(-t / 0.22)
    place(x, bp(noise(n), 250.0, 1200.0) * quiver, 0.01, 1.0)
    place(x, modes(0.6, [rng.uniform(110, 150)], [0.35], [0.18]) * (1.0 + 0.5 * np.sin(TAU * f * t_(n_(0.6)))), 0.0, 1.0)
    return finish(room(x, 0.25, 0.06), -3.0)


def step() -> np.ndarray:
    """A sandalled foot on beaten earth and grit."""
    n = n_(0.22)
    x = np.zeros(n)
    place(x, punch(0.08, rng.uniform(160, 190), rng.uniform(110, 125), 0.012, 0.018), 0.0, 0.38)
    place(x, crackle(0.12, rng.uniform(1500, 3500), 700.0, 5000.0, env(n_(0.12), 0.006, 0.035)), 0.004, 1.6)
    place(x, bp(noise(n_(0.08)), 400.0, 2200.0) * env(n_(0.08), 0.004, 0.02), 0.0, 0.7)
    return finish(x, -3.0)


# --- the scripted moments ------------------------------------------------------------

def pickup() -> np.ndarray:
    n = n_(0.35)
    x = np.zeros(n)
    place(x, modes(0.2, [420.0, 980.0, 1750.0], [1.0, 0.5, 0.25], [0.03, 0.02, 0.012]), 0.0, 0.9)
    place(x, bronze(0.35, 2200.0, 0.08, 0.7), 0.02, 0.25)
    place(x, bp(noise(n_(0.12)), 600.0, 3000.0) * swell(n_(0.12), 0.4), 0.0, 0.25)
    return finish(x, -4.0)


def lyre_note(freq: float, dur: float = 2.2) -> np.ndarray:
    n = n_(dur)
    t = t_(n)
    x = np.zeros(n)
    for k in range(1, 14):
        f = freq * k * (1.0 + 0.0003 * k * k)
        if f > SR * 0.45:
            break
        x += np.sin(TAU * f * t + rng.uniform(0, TAU)) * k ** -1.1 * np.exp(-t * (1.4 + 0.8 * k))
    x += lp(noise(n), 3500.0) * np.exp(-t * 250.0) * 0.4
    return x


def objective() -> np.ndarray:
    n = n_(2.4)
    x = np.zeros(n)
    place(x, lyre_note(329.63), 0.0, 0.8)
    place(x, lyre_note(493.88), 0.2, 0.7)
    return finish(room(x, 0.9, 0.18), -5.0)


def horn_blast(dur: float, base: float) -> np.ndarray:
    """A ram's horn: a breathy, buzzing tone that cracks up into its pitch."""
    n = n_(dur)
    t = t_(n)
    f = base * (1.0 - 0.12 * np.exp(-t / 0.08)) * (1.0 + 0.006 * np.sin(TAU * 4.6 * t))
    ph = np.cumsum(f) / SR
    tone = sum(np.sin(TAU * k * ph) * (k ** -0.9) for k in range(1, 18) if base * k < SR * 0.45)
    tone = peak_eq(tone, 1200.0, 1.5, 2.2)
    breath = bp(noise(n), 800.0, 3000.0) * 0.08
    e = np.clip(t / 0.07, 0, 1) * np.clip((dur - t) / 0.25, 0, 1)
    return (lp(tone, 4500.0) + breath) * e


def horn() -> np.ndarray:
    x = horn_blast(2.4, rng.uniform(158.0, 168.0))
    return finish(room(x, 1.6, 0.35, 4000.0), -2.0)


def alarm() -> np.ndarray:
    n = n_(1.8)
    x = np.zeros(n)
    place(x, horn_blast(0.5, 262.0), 0.0, 1.0)
    place(x, horn_blast(0.6, 262.0), 0.72, 1.0)
    return finish(room(x, 1.2, 0.3, 4000.0), -2.0)


def creak(dur: float, f0: float, f1: float, rough: float = 0.5) -> np.ndarray:
    """Timber grinding on timber: stick-slip pulses at a wandering rate."""
    n = n_(dur)
    t = t_(n)
    k = np.linspace(0.0, 1.0, n)
    rate = (f0 + (f1 - f0) * k) * (1.0 + 0.25 * np.sin(TAU * 1.7 * t) + 0.1 * np.sin(TAU * 6.3 * t))
    ph = np.cumsum(rate) / SR
    pulses = np.maximum(0.0, np.sin(TAU * ph)) ** 12 * (1.0 + rough * noise(n))
    body = bp(pulses, 180.0, 2400.0)
    body = peak_eq(peak_eq(body, 420.0, 4.0, 3.0), 1150.0, 5.0, 2.0)
    return body * np.clip(t / 0.15, 0, 1) * np.clip((dur - t) / 0.2, 0, 1)


def heavy_thud(dur: float = 0.6) -> np.ndarray:
    n = n_(dur)
    x = np.zeros(n)
    place(x, punch(dur, 120.0, 55.0, 0.04, 0.12, 2.0), 0.0, 0.7)
    place(x, modes(dur, [150.0, 330.0, 560.0, 910.0], [0.8, 0.55, 0.35, 0.2], [0.1, 0.07, 0.05, 0.03]), 0.0, 1.0)
    place(x, click(0.06, 300.0, 2500.0, 0.014), 0.0, 1.0)
    return x


def bar() -> np.ndarray:
    n = n_(1.8)
    x = np.zeros(n)
    place(x, creak(1.0, 18.0, 30.0), 0.0, 0.5)
    place(x, heavy_thud(0.7), 1.05, 1.0)
    return finish(room(x, 0.6, 0.15), -2.0)


def gate() -> np.ndarray:
    n = n_(3.6)
    x = np.zeros(n)
    place(x, creak(3.1, 9.0, 14.0, 0.8) * 1.0, 0.0, 0.7)
    place(x, lp(creak(3.1, 4.0, 6.0, 1.0), 400.0), 0.0, 0.9)
    place(x, heavy_thud(0.7), 2.95, 1.0)
    return finish(room(x, 1.0, 0.2), -2.0)


def knock() -> np.ndarray:
    """Knuckles on the hollow flank of the horse."""
    n = n_(1.3)
    x = np.zeros(n)
    for k in range(3):
        at = k * 0.36 + rng.uniform(-0.02, 0.02)
        place(x, modes(0.3, [170.0, 395.0, 660.0, 1010.0], [1.0, 0.55, 0.3, 0.15], [0.05, 0.035, 0.025, 0.015]), at, 1.0)
        place(x, click(0.03, 800.0, 4000.0, 0.004), at, 0.4)
    return finish(room(x, 0.7, 0.25, 2500.0), -2.0)


def hatch() -> np.ndarray:
    n = n_(1.3)
    x = np.zeros(n)
    place(x, creak(0.7, 14.0, 22.0, 0.6), 0.0, 0.6)
    place(x, heavy_thud(0.5), 0.75, 0.7)
    return finish(room(x, 0.5, 0.15), -3.0)


def fire_burst() -> np.ndarray:
    n = n_(1.6)
    x = np.zeros(n)
    roar = lp(noise(n), 700.0) * swell(n, 0.25, 1.5)
    place(x, roar, 0.0, 1.0)
    place(x, crackle(1.6, 60.0, 1500.0, 9000.0, swell(n, 0.3, 1.2)), 0.0, 2.5)
    return finish(x, -3.0)


def thunder() -> np.ndarray:
    n = n_(5.5)
    t = t_(n)
    x = np.zeros(n)
    place(x, hp(noise(n_(0.25)), 1500.0) * env(n_(0.25), 0.002, 0.05), 0.0, 0.8)
    rumble = lp(noise(n), 160.0, 4) * (np.exp(-t / 1.6) * np.clip(t / 0.15, 0, 1))
    rumble *= np.clip(1.0 + 0.6 * drift(n, 3.0), 0.1, 3.0)
    place(x, rumble, 0.03, 3.0)
    place(x, lp(noise(n), 90.0, 4) * np.exp(-np.maximum(t - 0.8, 0) / 1.4) * np.clip((t - 0.6) / 0.6, 0, 1), 0.0, 3.0)
    return finish(room(x, 2.0, 0.3, 1500.0), -1.0)


def helmet() -> np.ndarray:
    n = n_(0.8)
    x = np.zeros(n)
    place(x, bronze(0.8, 1150.0, 0.2, 0.8), 0.0, 0.6)
    place(x, thump(0.2, 120.0, 70.0, 0.02, 0.04), 0.0, 0.6)
    place(x, crackle(0.08, 2000.0, 1000.0, 4000.0, env(n_(0.08), 0.002, 0.03)), 0.0, 0.4)
    return finish(room(x, 0.3, 0.08), -4.0)


# --- voices ------------------------------------------------------------------------

def kokoro():
    global _kokoro
    if _kokoro is None:
        from kokoro_onnx import Kokoro
        _kokoro = Kokoro(str(_model_dir / "kokoro-v1.0.onnx"), str(_model_dir / "voices-v1.0.bin"))
    return _kokoro


def speak(voice: str, text: str = "", phonemes: str = "", speed: float = 1.0) -> np.ndarray:
    if phonemes:
        s, rate = kokoro().create(phonemes, voice=voice, speed=speed, is_phonemes=True)
    else:
        s, rate = kokoro().create(text, voice=voice, speed=speed, lang="en-gb")
    x = np.asarray(s, dtype=np.float64)
    loud = np.flatnonzero(np.abs(x) > 0.015)
    if loud.size:
        x = x[max(loud[0] - 200, 0): loud[-1] + 400]
    return signal.resample_poly(x, 147, 80)  # 24 kHz -> 44.1 kHz


def bend(x: np.ndarray, start: float, end: float) -> np.ndarray:
    """Plays a sound with its pitch (and pace) sliding from [start] to [end]."""
    rate = np.linspace(start, end, x.size)
    pos = np.cumsum(rate)
    pos = pos[pos < x.size - 1]
    # Read faster than it was written and its top would fold back down: cut it first.
    return np.interp(pos, np.arange(x.size), lp(x, SR * 0.45 / max(1.0, start, end)))


def strain(x: np.ndarray, drive: float = 2.6, presence: float = 1.6) -> np.ndarray:
    """A voice forced out of a body in pain or fury: driven into distortion,
    stripped of its boom, its bite brought forward."""
    x = x / max(np.abs(x).max(), 1e-9)
    x = np.tanh(drive * x) / np.tanh(drive)
    x = hp(x, 110.0)
    return peak_eq(x, 2600.0, 1.2, presence)


# Voices for the battlefield. bm_lewis is left out: given a bare cry it
# whispers. Each cry below is a voice and spelling that measured at least 80%
# voiced: some pairs come out as breath rather than a voice.
MEN = ["am_onyx", "am_fenrir", "am_eric", "am_liam", "am_michael", "am_adam", "bm_george", "bm_daniel", "am_puck"]
GRUNTS = [("am_fenrir", "hˈʌ!"), ("am_eric", "hˈɐːk!"), ("am_adam", "ˈʌɡ!"), ("bm_george", "ˈɐːh!"),
          ("am_liam", "hˈɐːk!"), ("am_michael", "ˈɐːh!"), ("am_puck", "hˈʌ!"), ("bm_fable", "hˈʌŋ!")]
HURTS = [("bm_george", "ˈɐːh!"), ("bm_george", "hˈʌ!"), ("am_onyx", "hˈʌ!"), ("bm_george", "ˈʌɡ!"), ("am_onyx", "ˈaɪ!")]
DEATHS = [("am_eric", "ˈɑːɡhh…"), ("am_liam", "ˈaɪːːː…"), ("bm_george", "ˈɔːːhh…"), ("bm_daniel", "ˈʌːːɡ…"),
          ("am_michael", "ˈɔːːhh…"), ("am_fenrir", "ˈaɪːːː…"), ("am_onyx", "ˈaɪːːː…"), ("am_puck", "ˈaɪːːː…")]


def grunt(i: int) -> np.ndarray:
    """A soldier hit but standing."""
    voice, ph = GRUNTS[i % len(GRUNTS)]
    x = speak(voice, phonemes=ph)
    x = bend(x, rng.uniform(1.0, 1.12), rng.uniform(0.86, 0.95))
    return finish(room(strain(x, 3.2), 0.25, 0.08), -1.0)


def hurt(i: int) -> np.ndarray:
    """The hero hit: one deep voice, close."""
    voice, ph = HURTS[i % len(HURTS)]
    x = speak(voice, phonemes=ph)
    x = bend(x, 0.96, 0.84)
    return finish(room(strain(x, 2.8), 0.2, 0.05), -1.0)


def death(i: int) -> np.ndarray:
    """A man's last cry: it rises, breaks and sinks."""
    voice, ph = DEATHS[i % len(DEATHS)]
    x = speak(voice, phonemes=ph, speed=0.8)
    x = bend(x, rng.uniform(1.0, 1.1), rng.uniform(0.66, 0.76))
    x *= np.linspace(1.0, 0.35, x.size) ** 0.8
    return finish(room(strain(x, 2.4), 0.3, 0.1), -1.0)


def shout(i: int) -> np.ndarray:
    """A Trojan watchman who has seen something in the dark."""
    words = ["Achaeans!", "To arms!", "Who goes there?", "Halt!", "Wake up! Wake up!", "Achaeans in the city!"][i % 6]
    x = speak(MEN[(i * 3 + 2) % len(MEN)], text=words, speed=1.12)
    x = bend(x, 1.04, 0.98)
    return finish(room(strain(x, 2.0, 2.0), 0.6, 0.18, 4000.0), -1.0)


# --- ambience ----------------------------------------------------------------------

def loopify(x: np.ndarray, length: int, fade: int) -> np.ndarray:
    """Cross-fades the [fade] samples past the end into the start, so that
    the loop has no seam. [x] must be at least length + fade long."""
    out = x[:length].copy()
    k = np.linspace(0.0, 1.0, fade)
    w_in = np.sin(k * np.pi / 2)
    w_out = np.cos(k * np.pi / 2)
    if out.ndim == 2:
        w_in = w_in[:, None]
        w_out = w_out[:, None]
    out[:fade] = out[:fade] * w_in + x[length:length + fade] * w_out
    return out


def pan(x: np.ndarray, p: float) -> np.ndarray:
    a = (p + 1.0) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1) * 1.4142


def scatter(bed: np.ndarray, length: int, sound: np.ndarray, at: float, gain: float, p: float) -> None:
    """Places a one-shot in a stereo loop, wrapping past the end."""
    st = pan(sound, p) * gain
    i = n_(at) % length
    m = min(st.shape[0], bed.shape[0] - i)
    bed[i:i + m] += st[:m]
    if st.shape[0] > m:
        rest = st[m:]
        bed[: rest.shape[0]] += rest


def hall(x: np.ndarray, seconds: float, wet: float, bright: float = 3500.0) -> np.ndarray:
    """Reverb for a loop: the tail that rings past the end is folded back
    onto the start, so the loop point has no seam."""
    m = n_(seconds)
    t = np.arange(m) / m
    ir = rng.standard_normal((m, 2)) * np.exp(-6.9 * t)[:, None]
    ir = lp(hp(ir, 150.0), bright)
    ir[: n_(0.02)] = 0.0
    ir /= np.sqrt(np.sum(ir * ir, axis=0))
    full = np.stack([signal.fftconvolve(x[:, c], ir[:, c]) for c in range(2)], axis=1)
    return x + wrap_fold(full, x.shape[0]) * wet


def looped(fn, x: np.ndarray) -> np.ndarray:
    """Runs a filter over a loop as if it had always been playing: over two
    copies end to end, keeping the second."""
    return fn(np.concatenate([x, x]))[x.shape[0]:]


def wind(n: int, cutoff: float, gusts: float) -> np.ndarray:
    sides = []
    for _ in range(2):
        w = lp(noise(n), cutoff, 2)
        sides.append(w * np.clip(1.0 + gusts * drift(n, 0.15), 0.15, 3.0))
    return np.stack(sides, axis=1)


def wrap_fold(bed: np.ndarray, length: int) -> np.ndarray:
    out = bed[:length].copy()
    rest = bed[length:]
    while rest.shape[0] > 0:
        out[: min(length, rest.shape[0])] += rest[:length]
        rest = rest[length:]
    return out


def amb_night(seconds: float = 24.0) -> np.ndarray:
    length = n_(seconds)
    fade = n_(3.0)
    bed = wind(length + fade, 380.0, 0.6) * 0.5
    bed = loopify(bed, length, fade)
    bed = np.concatenate([bed, np.zeros((n_(2.0), 2))])
    for c in range(5):
        f = rng.uniform(4100.0, 4800.0)
        p = rng.uniform(-0.9, 0.9)
        g = rng.uniform(0.03, 0.08)
        period = rng.uniform(0.55, 0.95)
        at = rng.uniform(0.0, period)
        while at < seconds:
            syll = rng.integers(2, 5)
            dur = syll / 28.0
            m = n_(dur)
            tt = t_(m)
            chirp = np.sin(TAU * f * tt) * np.maximum(0.0, np.sin(TAU * 28.0 * tt)) ** 2
            scatter(bed, length, chirp, at, g, p)
            at += period * rng.uniform(0.85, 1.2)
    for at in (7.0, 7.9, 8.35, 19.0, 19.6):
        m = n_(0.42)
        tt = t_(m)
        hoot = np.sin(TAU * np.cumsum(390.0 - 40.0 * tt / 0.42) / SR) * np.sin(np.pi * tt / 0.42) ** 1.5
        scatter(bed, length, lp(hoot, 900.0), at, 0.05, -0.6)
    return hall(wrap_fold(bed, length), 1.4, 0.25, 3000.0)


def amb_day(seconds: float = 24.0) -> np.ndarray:
    length = n_(seconds)
    fade = n_(3.0)
    total = length + fade
    t = t_(total)
    bed = wind(total, 520.0, 0.5) * 0.35
    for c in range(2):
        buzz = bp(noise(total), 4200.0, 7200.0)
        rate = rng.uniform(38.0, 55.0)
        cycle = 0.55 + 0.45 * np.sin(TAU * t / rng.uniform(6.0, 11.0) + rng.uniform(0, TAU))
        bed[:, c] += buzz * (0.5 + 0.5 * np.sin(TAU * rate * t)) ** 3 * cycle * 0.05
    bed = loopify(bed, length, fade)
    bed = np.concatenate([bed, np.zeros((n_(2.0), 2))])
    for _ in range(26):
        at = rng.uniform(0.0, seconds)
        p = rng.uniform(-0.9, 0.9)
        for k in range(rng.integers(2, 6)):
            m = n_(rng.uniform(0.05, 0.12))
            tt = np.linspace(0.0, 1.0, m)
            f0, f1 = rng.uniform(2600, 4200), rng.uniform(3000, 5200)
            chirp = np.sin(TAU * np.cumsum(f0 + (f1 - f0) * tt) / SR) * np.sin(np.pi * tt)
            scatter(bed, length, chirp, at + k * rng.uniform(0.09, 0.16), rng.uniform(0.008, 0.025), p)
    # A bronze-smith at work somewhere in the lower town.
    at = 3.0
    while at < seconds:
        for k in range(rng.integers(3, 7)):
            scatter(bed, length, lp(bronze(0.6, rng.uniform(1750, 1850), 0.15, 0.7), 5000.0), at + k * 0.42,
                    0.012, 0.55)
        at += rng.uniform(5.0, 9.0)
    return hall(wrap_fold(bed, length), 1.2, 0.18, 4000.0)


TALK = [
    "Pour me another cup.", "Ten years! Ten years of it!", "They burned their huts and sailed.",
    "To Athena, who has saved the city.", "Did you see the size of the thing?", "My father fought at the ships.",
    "Sing us the one about Heracles.", "More wine here!", "They say it is an offering.",
    "Tomorrow I will walk to the shore and look.", "Laocoon was a fool.", "Where is the singer?",
    "Ha! Ha ha ha!", "Drink, brother, drink!", "No more watches on the wall.", "The plain is empty at last.",
]
CROWD = ["am_adam", "am_echo", "am_eric", "am_liam", "am_michael", "am_puck", "bm_daniel", "bm_lewis", "bm_fable",
         "af_bella", "af_sarah", "bf_emma", "bf_lily", "af_nicole"]


def amb_feast(seconds: float = 24.0) -> np.ndarray:
    """The Trojans celebrating round the horse, heard from inside it."""
    length = n_(seconds)
    bed = np.zeros((length + n_(6.0), 2))
    lines = [speak(CROWD[i % len(CROWD)], text=TALK[i % len(TALK)], speed=rng.uniform(0.95, 1.15))
             for i in range(28)]
    for i, line in enumerate(lines):
        scatter(bed, length, line, rng.uniform(0.0, seconds), rng.uniform(0.25, 0.6), rng.uniform(-0.8, 0.8))
    beat = 60.0 / 104.0
    k = 0
    while k * beat < seconds:
        drum = thump(0.3, 140.0, 80.0, 0.02, 0.07) + pad(click(0.05, 300.0, 1500.0, 0.01), n_(0.3)) * 0.5
        scatter(bed, length, drum, k * beat, 0.5 if k % 4 == 0 else 0.3, 0.3)
        k += 1
    notes = [164.81, 174.61, 196.0, 220.0, 246.94, 293.66]
    at = 0.3
    while at < seconds:
        scatter(bed, length, lyre_note(notes[rng.integers(0, len(notes))] * 2.0, 1.8), at, 0.25, -0.4)
        at += rng.choice([beat, beat * 0.5, beat * 1.5])
    bed = wrap_fold(bed, length)
    # Through the planks: the timber keeps the low murmur and loses the rest.
    bed = looped(lambda b: lp(b, 650.0, 4) + peak_eq(lp(b, 300.0), 180.0, 2.0, 1.8) * 0.4, bed)
    return hall(bed, 1.8, 0.35, 1200.0)


def amb_battle(seconds: float = 24.0, cries: list = None) -> np.ndarray:
    """The fighting before the gate: a sea of men and bronze."""
    length = n_(seconds)
    fade = n_(3.0)
    total = length + fade
    roar = np.stack([bp(noise(total), 160.0, 1400.0) for _ in range(2)], axis=1)
    surge = 1.0 + 0.5 * np.clip(drift(total, 0.4), -0.8, 1.5)
    roar *= surge[:, None] * 0.25
    bed = loopify(roar, length, fade)
    bed = np.concatenate([bed, np.zeros((n_(3.0), 2))])
    for maker, count, gain in ((clang, 26, 0.12), (block, 30, 0.18), (hit_pierce, 14, 0.14), (hit_cut, 14, 0.14),
                               (whoosh_slash, 14, 0.06), (fall, 6, 0.12)):
        for _ in range(count):
            near = rng.uniform(0.15, 1.0)
            s = maker()
            s = lp(s, 1500.0 + 9000.0 * near)
            scatter(bed, length, s, rng.uniform(0.0, seconds), gain * near, rng.uniform(-1.0, 1.0))
    for _ in range(26):
        s = cries[rng.integers(0, len(cries))]
        near = rng.uniform(0.2, 0.8)
        scatter(bed, length, lp(s, 1200.0 + 4000.0 * near), rng.uniform(0.0, seconds), 0.2 * near,
                rng.uniform(-1.0, 1.0))
    scatter(bed, length, lp(horn_blast(2.0, 150.0), 2500.0), 9.0, 0.12, -0.7)
    return hall(wrap_fold(bed, length), 2.4, 0.4, 3000.0)


def amb_sack(seconds: float = 24.0, cries: list = None, battle: np.ndarray = None) -> np.ndarray:
    """The city burning: fire roaring in the roofs, timber falling, fighting
    in the streets."""
    length = n_(seconds)
    fade = n_(3.0)
    total = length + fade
    t = t_(total)
    roar = np.stack([lp(noise(total), 600.0, 2) * (1.0 + 0.4 * np.sin(TAU * t / 7.0 + c)) for c in range(2)], axis=1)
    crack = np.stack([crackle(total / SR, 90.0, 1500.0, 9000.0) for _ in range(2)], axis=1)
    bed = loopify(roar * 0.5 + crack * 1.5, length, fade)
    bed = np.concatenate([bed, np.zeros((n_(3.0), 2))])
    for at in (4.0, 15.0):
        crash = heavy_thud(1.0) + crackle(1.0, 400.0, 800.0, 6000.0, env(n_(1.0), 0.01, 0.35)) * 2.0
        scatter(bed, length, crash, at, 0.3, rng.uniform(-0.7, 0.7))
    for _ in range(16):
        s = cries[rng.integers(0, len(cries))]
        near = rng.uniform(0.2, 0.7)
        scatter(bed, length, lp(s, 1500.0 + 3000.0 * near), rng.uniform(0.0, seconds), 0.2 * near,
                rng.uniform(-1.0, 1.0))
    out = hall(wrap_fold(bed, length), 2.0, 0.3, 3000.0)
    return out + battle * 0.45


def far(x: np.ndarray) -> np.ndarray:
    """The same fighting heard from inside the walls."""
    return hall(looped(lambda b: lp(b, 900.0, 3), x), 2.6, 0.5, 1500.0)


def amb_level(x: np.ndarray, target_db: float) -> np.ndarray:
    x = looped(lambda b: hp(b, 40.0), x)
    rms = np.sqrt(np.mean(x * x))
    x = x * 10 ** (target_db / 20.0) / max(rms, 1e-9)
    return np.tanh(x * 1.1) / 1.1


# --- output -------------------------------------------------------------------------

def write_ogg(path: Path, x: np.ndarray, quality: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    channels = 1 if x.ndim == 1 else x.shape[1]
    pcm = (np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2").tobytes()
    subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", str(channels), "-i", "-",
         "-c:a", "libvorbis", "-q:a", str(quality), "-map_metadata", "-1", "-fflags", "+bitexact",
         "-flags:a", "+bitexact", str(path)],
        input=pcm, check=True)


# name -> (maker, variants). A maker takes no argument, or the variant index.
EFFECTS = {
    "whoosh_thrust": (whoosh_thrust, 4), "whoosh_slash": (whoosh_slash, 4), "whoosh_throw": (whoosh_throw, 3),
    "hit_pierce": (hit_pierce, 5), "hit_cut": (hit_cut, 5), "hit_head": (hit_head, 4),
    "block": (block, 5), "clang": (clang, 4), "stab": (stab, 3), "fall": (fall, 4), "spear_stick": (spear_stick, 3),
    "step": (step, 8),
    "grunt": (grunt, 8), "hurt": (hurt, 5), "death": (death, 8), "shout": (shout, 6),
    "pickup": (pickup, 1), "objective": (objective, 1), "horn": (horn, 1), "alarm": (alarm, 1), "bar": (bar, 1),
    "gate": (gate, 1), "knock": (knock, 1), "hatch": (hatch, 1), "fire": (fire_burst, 2), "thunder": (thunder, 2),
    "helmet": (helmet, 1),
}
VOICED = {"grunt", "hurt", "death", "shout"}
AMBIENCE = ["night", "day", "feast", "battle", "battle_far", "sack"]


def main() -> None:
    global rng, _model_dir
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="/opt/kokoro")
    ap.add_argument("names", nargs="*", help="effects or ambiences to render (default: all)")
    opts = ap.parse_args()
    _model_dir = Path(opts.model)
    wanted = set(opts.names) or set(EFFECTS) | set(AMBIENCE)
    unknown = wanted - set(EFFECTS) - set(AMBIENCE)
    if unknown:
        sys.exit("unknown: " + ", ".join(sorted(unknown)))

    index_path = SFX_OUT / "index.json"
    index = json.loads(index_path.read_text()) if index_path.exists() else {}
    for name, (maker, count) in EFFECTS.items():
        if name not in wanted:
            continue
        sizes = []
        for i in range(count):
            # Each variant has its own seed, so rendering one never changes another.
            rng = np.random.default_rng(abs(hash_name(name)) + i)
            x = maker(i) if name in VOICED else maker()
            write_ogg(SFX_OUT / f"{name}_{i + 1}.ogg", x, 5)
            sizes.append(x.size / SR)
        index[name] = count
        print(f"{name:<14} {count} x {min(sizes):.2f}-{max(sizes):.2f} s")
    index_path.parent.mkdir(parents=True, exist_ok=True)
    index_path.write_text(json.dumps(dict(sorted(index.items())), indent=2) + "\n")

    if wanted & set(AMBIENCE):
        rng = np.random.default_rng(1184)
        cries = [grunt(i) for i in range(8)] + [death(i) for i in range(8)] + [shout(i) for i in (1, 3)]
        battle = amb_battle(cries=cries)
        made = {
            "night": lambda: amb_night(), "day": lambda: amb_day(), "feast": lambda: amb_feast(),
            "battle": lambda: battle, "battle_far": lambda: far(battle),
            "sack": lambda: amb_sack(cries=cries, battle=battle),
        }
        levels = {"night": -24.0, "day": -25.0, "feast": -21.0, "battle": -18.0, "battle_far": -22.0, "sack": -18.0}
        for name in AMBIENCE:
            if name not in wanted:
                continue
            x = amb_level(made[name](), levels[name])
            write_ogg(AMB_OUT / f"{name}.ogg", x, 2)
            print(f"{name:<14} {x.shape[0] / SR:.1f} s loop  {(AMB_OUT / (name + '.ogg')).stat().st_size // 1024} KB")


def hash_name(name: str) -> int:
    # Python's own hash() of a string changes from run to run.
    h = 2166136261
    for ch in name.encode():
        h = ((h ^ ch) * 16777619) & 0xFFFFFFFF
    return h


if __name__ == "__main__":
    main()
