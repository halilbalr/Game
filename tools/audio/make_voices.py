#!/usr/bin/env python3
"""Renders every spoken line of the missions to OGG files.

    python3 tools/audio/make_voices.py [--model DIR] [--only horse/helen_1]

Reads assets/data/missions/*.json and writes
assets/audio/voice/<mission>/<key>.ogg for each entry of "lines", and
assets/audio/voice/<mission>/text_<key>.ogg for the narrated texts (intro,
ending, defeats). The game looks files up by those names; a line with no file
is simply shown without a voice.

The voices are synthetic: Kokoro v1.0 (Apache-2.0), run locally through
kokoro-onnx. Nothing here is a recording of a person. The model is not part of
the repository; fetch kokoro-v1.0.onnx and voices-v1.0.bin from the
kokoro-onnx releases and point --model at the directory that holds them.

Needs: pip install kokoro-onnx numpy scipy; ffmpeg with libvorbis.
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
from scipy import signal

ROOT = Path(__file__).resolve().parents[2]
MISSIONS = ROOT / "assets" / "data" / "missions"
OUT = ROOT / "assets" / "audio" / "voice"
RATE = 24000
LANG = "en-gb"

# Speaker -> (voice, speed, pitch, effect). Pitch below 1 deepens the voice:
# the line is spoken faster by that factor and then slowed back down.
CAST = {
    "": ("bm_fable", 0.92, 0.97, "narrator"),
    "Menelaus": ("bm_lewis", 0.98, 0.95, "dry"),
    "Diomedes": ("bm_daniel", 1.0, 0.97, "dry"),
    "Helen": ("bf_isabella", 0.9, 1.0, "outside"),
    "Sinon": ("am_echo", 1.0, 1.0, "outside"),
    "Athena": ("bf_alice", 0.86, 0.98, "god"),
    "Agamemnon": ("am_fenrir", 0.98, 0.93, "field"),
    "Deiphobus": ("am_eric", 0.95, 0.95, "dry"),
    "Andromache": ("bf_emma", 0.93, 1.0, "dry"),
    "Hector": ("bm_george", 0.95, 0.94, "dry"),
    "Paris": ("am_michael", 0.98, 1.0, "dry"),
    "Trojan": ("am_liam", 1.08, 0.98, "field"),
    "Patroclus": ("am_adam", 0.98, 0.98, "dry"),
    "Apollo": ("am_onyx", 0.84, 0.88, "god"),
}

# Narrated entries of "text" (the source note after a blank line is not read).
NARRATED = ["intro", "end_text", "death_text", "alarm_text", "anticlus_text"]

# The model's dictionary does not know Homer. Phonemes for the names it gets
# wrong, in the notation espeak-ng produces for British English.
LEXICON = {
    "Menelaus": "mˌɛnɪlˈeɪəs",
    "Diomedes": "dˌaɪəmˈiːdiːz",
    "Aegialeia": "ˌiːdʒɪəlˈaɪə",
    "Anticlus": "ˈantɪkləs",
    "Laodamia": "leɪˌɒdəmˈaɪə",
    "Sinon": "sˈaɪnɒn",
    "Tenedos": "tˈɛnɪdɒs",
    "Laertes": "leɪˈɜːtiːz",
    "Odysseus": "əʊdˈɪsjuːs",
    "Scaean": "sˈiːən",
    "Deiphobus": "diːˈɪfəbəs",
    "Atreides": "ɐtɹˈaɪdiːz",
    "Achaeans": "ɐkˈiːənz",
    "Achaean": "ɐkˈiːən",
    "Ilios": "ˈɪlɪɒs",
    "Priam": "pɹˈaɪəm",
    "Patroclus": "pətɹˈɒkləs",
    "Myrmidons": "mˈɜːmɪdɒnz",
    "Euphorbus": "juːfˈɔːbəs",
    "Panthous": "pˈanθəʊəs",
    "Lycians": "lˈɪsiənz",
    "Andromache": "andɹˈɒməki",
    "Scamander": "skəmˈandə",
    "Argos": "ˈɑːɡɒs",
    "Agamemnon": "ˌaɡəmˈɛmnɒn",
}
NAME = re.compile(r"\b(" + "|".join(sorted(LEXICON, key=len, reverse=True)) + r")\b")


def phonemes(kokoro, text: str) -> str:
    """Phonemes for a sentence, with the lexicon's names spliced in."""
    out = []
    pos = 0
    for m in NAME.finditer(text):
        before = text[pos:m.start()]
        if before.strip():
            out.append(kokoro.tokenizer.phonemize(before, LANG).strip())
        out.append(LEXICON[m.group(1)])
        pos = m.end()
    rest = text[pos:]
    if re.search(r"\w", rest):
        out.append(kokoro.tokenizer.phonemize(rest, LANG).strip())
    elif rest.strip():
        # Closing punctuation only: keep it so the sentence falls or rises.
        out[-1] += rest.strip()[0]
    joined = " ".join(p for p in out if p)
    return re.sub(r"\s+([,.!?;:])", r"\1", joined)


def trim(x: np.ndarray, pad: float = 0.03) -> np.ndarray:
    loud = np.flatnonzero(np.abs(x) > 0.012)
    if loud.size == 0:
        return x
    a = max(int(loud[0] - pad * RATE), 0)
    b = min(int(loud[-1] + pad * RATE), x.size)
    return x[a:b]


def reverb(x: np.ndarray, seconds: float, wet: float, bright: float, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = int(seconds * RATE)
    ir = rng.standard_normal(n) * np.exp(-6.9 * np.arange(n) / n)
    b, a = signal.butter(2, bright / (RATE / 2), "low")
    ir = signal.lfilter(b, a, ir)
    ir[: int(0.012 * RATE)] = 0.0
    ir /= np.sqrt(np.sum(ir * ir))
    tail = signal.fftconvolve(x, ir)
    out = np.zeros(tail.size)
    out[: x.size] = x
    return out + tail * wet


def effect(x: np.ndarray, kind: str, seed: int) -> np.ndarray:
    if kind == "narrator":
        return reverb(x, 0.9, 0.10, 5000.0, seed)
    if kind == "god":
        # A voice with no mouth: a long bright hall.
        return reverb(x, 2.6, 0.42, 6500.0, seed)
    if kind == "outside":
        # Heard through the planks of the horse.
        b, a = signal.butter(3, 1500.0 / (RATE / 2), "low")
        return reverb(signal.lfilter(b, a, x) * 1.5, 0.7, 0.22, 2500.0, seed)
    if kind == "field":
        # A shout across open ground.
        b, a = signal.butter(2, 250.0 / (RATE / 2), "high")
        return reverb(signal.lfilter(b, a, x), 1.3, 0.28, 3500.0, seed)
    return reverb(x, 0.35, 0.06, 4500.0, seed)


def level(x: np.ndarray, target_db: float = -19.0) -> np.ndarray:
    speech = x[np.abs(x) > 0.01]
    rms = np.sqrt(np.mean(speech * speech)) if speech.size else 1.0
    x = x * (10 ** (target_db / 20.0) / max(rms, 1e-6))
    # Soft ceiling instead of hard clipping.
    return np.tanh(x * 1.1) / 1.1


def render(kokoro, speaker: str, text: str, seed: int) -> np.ndarray:
    voice, speed, pitch, kind = CAST.get(speaker, CAST[""])
    parts = []
    for sentence in re.split(r"(?<=[.!?])[\"']?\s+", text.strip()):
        if not re.search(r"\w", sentence):
            continue
        ph = phonemes(kokoro, sentence)
        samples, rate = kokoro.create(ph, voice=voice, speed=speed / pitch, is_phonemes=True)
        assert rate == RATE
        x = trim(np.asarray(samples, dtype=np.float64))
        if pitch != 1.0:
            x = signal.resample(x, int(round(x.size / pitch)))
        parts.append(x)
        parts.append(np.zeros(int(0.30 * RATE)))
    x = np.concatenate(parts[:-1])
    x = effect(level(x), kind, seed)
    fade = int(0.01 * RATE)
    x[:fade] *= np.linspace(0.0, 1.0, fade)
    x[-fade:] *= np.linspace(1.0, 0.0, fade)
    return np.clip(x, -1.0, 1.0)


def write_ogg(path: Path, x: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = (x * 32767.0).astype("<i2").tobytes()
    subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-y", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-",
         "-c:a", "libvorbis", "-q:a", "3", "-map_metadata", "-1", "-fflags", "+bitexact",
         "-flags:a", "+bitexact", str(path)],
        input=pcm, check=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="/opt/kokoro")
    ap.add_argument("--only", default="", help="mission/key to render alone")
    opts = ap.parse_args()
    from kokoro_onnx import Kokoro
    model = Path(opts.model)
    kokoro = Kokoro(str(model / "kokoro-v1.0.onnx"), str(model / "voices-v1.0.bin"))

    jobs = []
    for path in sorted(MISSIONS.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        mission = path.stem
        for key, entry in data.get("lines", {}).items():
            jobs.append((mission, key, entry[0], entry[1]))
        for key in NARRATED:
            body = data.get("text", {}).get(key, "")
            if body:
                jobs.append((mission, "text_" + key, "", body.split("\n\n")[0]))

    total = 0.0
    for i, (mission, key, speaker, text) in enumerate(jobs):
        if opts.only and opts.only != f"{mission}/{key}":
            continue
        if speaker not in CAST:
            print(f"no voice cast for '{speaker}', using the narrator", file=sys.stderr)
        x = render(kokoro, speaker, text, seed=1000 + i)
        write_ogg(OUT / mission / f"{key}.ogg", x)
        total += x.size / RATE
        print(f"{mission}/{key:<18} {x.size / RATE:5.1f} s  {speaker or 'narrator'}")
    print(f"{total:.0f} s of speech")


if __name__ == "__main__":
    main()
