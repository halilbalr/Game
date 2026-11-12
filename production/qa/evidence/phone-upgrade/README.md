# Evidence: phone upgrade (sharper picture, voices, music, skippable scenes)

Captured on 2026-11-12. No phone was available here. Files `01`-`05` are from
the desktop engine in phone mode (`--mobile --phone`) in a window the shape of
an iPhone held sideways; `06`-`08` are from the packed Artifact page in
headless Chromium emulating a 440 x 956 touch screen. Both draw with software
renderers, so they show layout and legibility, not speed. Nothing here was
heard: the machine has no audio device.

```
godot --path . --windowed --resolution 1434x660 --fixed-fps 60 -- --mobile --phone --mission=gate --autoplay --stop=battle --shot=/abs/out.png
```

| File | What it shows |
|---|---|
| `01-menu-phone.png` | Title screen at the phone scale in the bundled faces (Cinzel capitals, Crimson Pro text): every entry inside the frame |
| `02-title-card-skip.png` | The narrated title card: only SKIP and Pause are offered while it is up |
| `03-fight-phone-layout.png` | Battle at the oak: the phone button layout with fitted labels, speech at the top, the hint and the weapon line between the thumbs |
| `04-pause-phone.png` | Pause on a phone: the options scroll inside their panel |
| `05-speech-in-the-horse.png` | A spoken line inside the horse with SKIP beside Pause |
| `06-browser-upright-menu.png` | The Artifact page on an upright phone: the game turned a quarter to fill the long side |
| `07-browser-skip-by-touch.png` | Before and after a finger on SKIP (turned upright for reading): the tap lands through the rotated canvas and the scene jumps to the next thing to do, with USE offered |
| `08-artifact-card-phone.png` | The Artifact's own title card on a phone: keyboard list hidden, the sideways note shown |

## Run results

- **Run result: OBSERVED** — text and buttons are legible at phone size and nothing overlaps — `01`, `03`, `04`, `05`.
- **Run result: OBSERVED** — the page sizes the canvas at the screen's own density: with a device pixel ratio of 3 on a 440 x 956 screen the canvas measured 2868 x 1320, turned (`canvas.width`, `canvas.height` read from the page).
- **Run result: OBSERVED** — touches map through the turn: a tap at the upright-screen position of THE WOODEN HORSE started that mission; a tap on SKIP skipped the scene — `06`, `07`.
- **Run result: OBSERVED** — scenes skip, by Enter in a desktop browser and by SKIP on touch, and land on the next interaction — `07`.
- **Run result: OBSERVED** — audio plumbing in the browser: the page's audio engine received the three music tracks and the narration, playback started, and a heard line was released from memory (instrumented copy of the page, counting the engine's register, start and release calls).
- **Run result: NOT VERIFIED** — how the voices and the music sound. Checked by measurement only: the phonemes fed to the voice model for each Greek name, and each track's loudness, spectral balance and loop seam.
- **Run result: NOT VERIFIED** — frame rate at any graphics level on a real phone, and the look at full 3x density (software rendering at that size was too slow to capture here).
- **Run result: NOT VERIFIED** — the claude.ai app's own behaviour around the page: safe areas, whether it rotates with the phone.

## What the automated checks cover

- 73 tests, including a new one for the phone button layout: every button on screen, at least 10 mm across on a 6.9-inch phone, none touching another or the stick, Pause or Skip.
- Both missions finished by the scripted player with real input in desktop, phone (`--mobile --phone`) and browser (`--web`) modes, voices and waits included, and by the self-playing script.

## Defects found by looking, now fixed

- Elements meant to be hidden on the Artifact page (the keyboard list on a phone, the title card after Play) could stay visible where the host page has no `[hidden]` rule of its own.
- The objective's diamond marker was a glyph the bundled typefaces do not have; in a browser it showed as an empty box. It is drawn now.
- Fight-button labels were under 4 pt on a phone. Phone buttons now have their own larger layout and each label is fitted to its button.
- Speech and notices timed themselves by the wall clock, so a paused game let a line expire. They count game time now.
