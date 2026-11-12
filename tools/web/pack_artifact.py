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
