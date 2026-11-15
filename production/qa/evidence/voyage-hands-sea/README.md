# Evidence: hands on the work, flute music, a more lifelike sea

From the owner's notes on the sea levels (2026-11-15): the rowers' hands did
not touch their oars; when Odysseus is tied to the mast or does something, he
should be seen doing it, not just standing; flute music in the spirit of a
modern film score for the Odyssey; more realistic scenery; water splashing on
the camera.

Captured on the Linux engine (Forward+, software Vulkan) at 960 x 540 or
1280 x 720, and in headless Chromium for the web build.

| Shot | What it shows |
|---|---|
| `01-rowers-hands-on-oars.jpg` | Each oar laid from its oarlock through the rower's two hands, at every point of the stroke |
| `02-ship-oarsmen-side.jpg` | The oarsmen seated on their thwarts, leaning into the stroke |
| `03-helm-hands-on-tiller.jpg` | At the stern Odysseus holds the tiller; it swings as he steers |
| `04-mast-being-tied.jpg` | Two of the crew bind him to the mast, turn on turn, while the story is told |
| `05-mast-bound-straining.jpg` | Bound: his wrists in the rope; he strains harder the longer he listens to the song |
| `06-cyclops-raising-the-bowl.jpg` | The ivy-wood bowl lifted up to the giant |
| `07-stake-in-hand.jpg` | The olive stake carried, then held in the fire and driven in (daylight test stage, `--act=fire`) |
| `08-under-the-ram.jpg` | Clinging under the ram, low among the flock, past the giant at the door |
| `09-chopping.jpg` | Hacking the stake from the club (`--act=chop`) |
| `10-shallows-and-surf.jpg` | Turquoise shallows over sand and surf breaking at the waterline, from a baked map of the sea floor |
| `11-island-trees-maquis.jpg` | Islands clothed in holm oak, olive, fig, maquis and boulders |
| `12-water-on-the-lens.jpg` | Drops on the view after spray: each bends the picture behind it |
| `13-strait-at-the-tiller.jpg` | The strait, hands on the tiller |

## Runs

| Check | Result |
|---|---|
| `tests/run_tests.gd` | 99 tests, 0 failed |
| `test_every_manned_oar_passes_through_the_rowers_hands` | Watched failing on the old fixed-angle oars (hands 0.19 m off), passing now |
| `--mission=cyclops` / `sirens` with `--bot --god`, plain, `--mobile --phone`, `--web` | All six: MISSION COMPLETE, no script errors |
| `--mission=gate --bot --god`, `--mission=horse --bot --god --noalarm` | Both complete |

## Fixed on the way

- **Water inside the ship.** Wave crests showed through the deck; the sea is
  now kept out of the hull's footprint.
- **Sandbars in the troughs.** The shallow shelf round each island showed
  through the swell; the bottom now falls away below the strand.
- **A surf strip under the waves.** A first attempt laid foam on a separate
  strip, which the coarser wave mesh covered in places; it was replaced by
  foam drawn by the sea itself from the floor map.

## Music

`sea` and `odyssey` are original pieces made for this game, in the manner of
a modern film score for the Odyssey: a breathy wooden flute (whole phrases in
one breath, with slides, grace notes and late vibrato), drones, frame drums,
a seven-beat measure for danger. No existing score is quoted or imitated note
for note. Checked by spectrogram, not by ear (no audio device here).

## Not verified

How the music and effects sound; frame rate on a real phone with the denser
islands (phones get fewer trees and shrubs and no tree shadows).
