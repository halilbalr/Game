#!/usr/bin/env python3
"""Packs a Godot web export into the files of a claude.ai Artifact.

    godot --headless --path . --export-release "Web" builds/web/index.html
    python3 tools/web/pack_artifact.py

Reads builds/web/ and writes builds/artifact/:

    the-odyssey.html                the page (Godot's loader script inlined)
    engine.wasm.gz.txt              the engine, gzipped then base64
    game.pck.txt                    the game data, base64
    index.audio.worklet.js          Godot's audio worklets, as exported
    index.audio.position.worklet.js

The engine is 38 MB of WebAssembly; an Artifact takes binary files up to 15 MB
and text files up to 16 MB, so it travels as base64 text of its gzip (about
12.5 MB) and the page unpacks it in the browser.
"""

import base64
import gzip
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WEB = ROOT / "builds" / "web"
OUT = ROOT / "builds" / "artifact"
SHELL = Path(__file__).with_name("artifact_shell.html")
TEXT_LIMIT = 16 * 1024 * 1024
POINTER = (
    "computePosition:function(evt,rect){const canvas=GodotConfig.canvas;"
    "const rw=canvas.width/rect.width;const rh=canvas.height/rect.height;"
    "const x=(evt.clientX-rect.x)*rw;const y=(evt.clientY-rect.y)*rh;return[x,y]}"
)
AUDIO = "var GodotAudio={MAX_VOLUME_CHANNELS:"
AUDIO_HOOK = (
    "window.__odysseyDropSample=function(id){const s=GodotAudio.Sample.getSampleOrNull(id);"
    "if(s!=null){s.clear();return true}return false};"
)
POINTER_TURNED = (
    "computePosition:function(evt,rect){const canvas=GodotConfig.canvas;"
    "if(window.__odysseyTurned){const u=(evt.clientY-rect.y)/rect.height;"
    "const v=1-(evt.clientX-rect.x)/rect.width;return[u*canvas.width,v*canvas.height]}"
    "const rw=canvas.width/rect.width;const rh=canvas.height/rect.height;"
    "const x=(evt.clientX-rect.x)*rw;const y=(evt.clientY-rect.y)*rh;return[x,y]}"
)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    wasm = (WEB / "index.wasm").read_bytes()
    wasm_text = base64.b64encode(gzip.compress(wasm, compresslevel=9, mtime=0))
    (OUT / "engine.wasm.gz.txt").write_bytes(wasm_text)

    pck = (WEB / "index.pck").read_bytes()
    pck_text = base64.b64encode(pck)
    (OUT / "game.pck.txt").write_bytes(pck_text)

    for name in ("index.audio.worklet.js", "index.audio.position.worklet.js"):
        shutil.copyfile(WEB / name, OUT / name)

    # Take the engine configuration from the page Godot exported, so file
    # sizes and options always match this build.
    exported = (WEB / "index.html").read_text(encoding="utf-8")
    match = re.search(r"const GODOT_CONFIG = (\{.*?\});", exported)
    if match is None:
        raise SystemExit("GODOT_CONFIG not found in builds/web/index.html")
    config = json.loads(match.group(1))

    engine_js = (WEB / "index.js").read_text(encoding="utf-8")
    if "</script" in engine_js.lower():
        raise SystemExit("index.js contains </script and cannot be inlined")
    # On a phone held upright the page turns the game a quarter (see the
    # shell). The engine maps a finger to the canvas assuming it is upright,
    # so teach that one function about the turn.
    if POINTER not in engine_js:
        raise SystemExit("the engine's pointer mapping has changed; update POINTER in pack_artifact.py")
    engine_js = engine_js.replace(POINTER, POINTER_TURNED)
    # The engine decodes every sound a page plays into the browser's audio
    # engine and never releases one. Give the game a way to release a spoken
    # line once it has been heard (see Sfx._forget).
    if AUDIO not in engine_js:
        raise SystemExit("the engine's audio library has changed; update AUDIO in pack_artifact.py")
    engine_js = engine_js.replace(AUDIO, AUDIO_HOOK + AUDIO, 1)

    hero = OUT / "hero.jpg"
    hero_uri = ""
    if hero.exists():
        hero_uri = "data:image/jpeg;base64," + base64.b64encode(hero.read_bytes()).decode("ascii")

    page = SHELL.read_text(encoding="utf-8")
    page = page.replace("/*__GODOT_ENGINE__*/", engine_js)
    page = page.replace("/*__GODOT_CONFIG__*/", json.dumps(config))
    page = page.replace("/*__HERO__*/", hero_uri)
    page = page.replace("/*__WASM_TEXT_SIZE__*/", str(len(wasm_text)))
    page = page.replace("/*__PCK_TEXT_SIZE__*/", str(len(pck_text)))
    (OUT / "the-odyssey.html").write_text(page, encoding="utf-8")

    for path in sorted(OUT.iterdir()):
        size = path.stat().st_size
        flag = "  OVER THE 16 MB LIMIT" if size > TEXT_LIMIT else ""
        print(f"{size:>10}  {path.name}{flag}")


if __name__ == "__main__":
    main()
