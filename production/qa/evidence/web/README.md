# Evidence: web build and Artifact

Captured on 2026-11-12 from the exported web build (Godot 4.6, single-threaded
WebAssembly, WebGL 2 / Compatibility renderer) running in headless Chromium
with software WebGL. `01`, `02` and `04` were loaded through the packed
Artifact page inside a copy of the publish skeleton; `03` through Godot's own
launcher page.

| File | What it shows |
|---|---|
| `01-artifact-title-card.png` | The Artifact page at rest: title card, Play buttons, "Ready. Press Play.", controls |
| `02-game-menu-in-browser.png` | After Play: the game's menu drawn in the browser (no Quit entry on the web) |
| `03-city-in-browser.png` | Walk the City in the browser: South Gate, HUD, "Click to take control" prompt |
| `04-mission-intro-in-browser.png` | The Scaean Gate mission's title card in the browser |

## Run results

- **Run result: OBSERVED** — the page unpacks the engine (12.5 MB of base64 gzip) and the game boots: engine up in 0.5 s, city built in about 4 s, navigation baked in about 5 s, browser console free of errors.
- **Run result: OBSERVED** — menu click starts a mission; a click on the game captures the pointer; key input reaches the game.
- **Run result: NOT VERIFIED** — the published Artifact itself, inside claude.ai's frame. Its content-security policy could not be reproduced locally. If WebAssembly or the page's own files were blocked there, the title card would show "The game could not start" with the reason.
- **Run result: NOT VERIFIED** — frame rate on a real graphics card, sound in a browser, touch play in a phone browser, and behaviour in Firefox and Safari.

## Defects found on the way, now fixed

- Crouch was on Ctrl: with W held that is Ctrl+W, which closes a browser tab. In a browser crouch is C only.
- The sound bank was built on a worker thread, which a single-threaded web build does not have. It is now built a sound at a time between frames there.
- The pointer was requested without a click, which browsers refuse. The game now takes it on the first click and falls back to turning with the free cursor if the page refuses.
- The OpenGL renderer showed the scene brighter and hazier than the Vulkan ones; exposure, fog and the tonemapper are adjusted for it.
