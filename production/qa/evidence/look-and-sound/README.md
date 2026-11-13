# Evidence: the jumping view and the fight sounds

Two reports from the owner playing the Artifact on an iPhone (2026-11-13):
the view jumps around when looking, above all while moving at the same time;
the sounds of fighting need to be better.

## The jumping view

**Cause, found and reproduced in the browser build.** Two synthetic fingers
were sent to the exported game in Chromium (a 956 x 440 touch screen): one
on the stick, one looking, each moving 10 pixels at a time. The game logged
what the engine reported for each drag beside the movement measured from the
finger's own last position:

```
touch drag 1 moved (19.0, -19.0) engine relative (-1019.0, 227.0)
touch drag 2 moved (19.0, 0.0)   engine relative (1340.0, 378.0)
touch drag 2 moved (19.0, 0.0)   engine relative (1057.0, -227.0)
touch drag 1 moved (19.0, -19.0) engine relative (-1038.0, 208.0)
touch drag 2 moved (19.0, 0.0)   engine relative (1057.0, -208.0)
```

With one finger down the engine's figure is right. With two it measures each
drag from whichever finger came first in the previous touch event, and a
10-pixel movement arrives as about 1,000 units: some 240 degrees of turn in a
single event. The look code used that figure. It now works the movement out
from each finger's last position.

- **Run result: OBSERVED** — the cause, in the browser build, as above.
- **Regression test** — `test_look_drag_with_two_thumbs_down_turns_by_the_distance_moved`
  (`tests/integration/touch_controls_test.gd`). Watched failing against the old
  code (the view turned 2.34 rad for a 10-unit movement; 0.042 expected), then
  passing.
- **Also fixed: walking stutter.** The body moves in fixed 60 Hz physics steps
  while a phone draws at its own uneven rate; the eye is now drawn between the
  body's last two steps. Not measurable here (software rendering, fixed frame
  rate); it follows the standard fixed-timestep interpolation.
- **Also removed: start-up stutter in a browser.** Effects used to be built
  while the game ran, about 25 seconds of the main thread in slices; during
  that time every frame could hitch. All sound is now rendered in advance.
- **Run result: NOT VERIFIED** — on a real phone.

## The fight sounds

`01-combat-sounds.png`: waveform (left, 1.2 s across) and spectrum (right,
0-16 kHz, 50 dB range) of one variant of each combat sound.

| Before | After |
|---|---|
| One version of each sound | 3-8 versions each, picked at random, never the same twice running, with small pitch and level changes |
| 22 kHz: nothing above 11 kHz, so bronze sounded dull | 44.1 kHz |
| One "whoosh" for every weapon, played at the start of the wind-up | Separate thrust, cut and throw sounds, timed to the swing itself |
| One "hit" for every blow | Spear wounds, sword wounds and helmet strikes, chosen by `Sfx.strike` from the weapon and where it landed |
| Grunts and death cries as buzzing tones | Human cries from the speech model, driven into distortion |
| A soft thud when a man fell | Knees, body, then his gear rattling, timed to when the body reaches the ground |
| Impacts with their weight below 150 Hz | Weight carried by overtones a phone speaker can play: under 150 Hz down from 80-97% of the energy to 7-58% |

- **Run result: OBSERVED** — every combat sound fires in a real fight: the
  scripted player in the arena (`--scene=arena --autoplay --bot`) set off
  thrust and cut swings, spear and sword wounds, head hits, blocks, grunts,
  death cries, falls, throws and the hero's own pain, each from several
  variants.
- **Run result: OBSERVED** — every ambience loop joins without a seam: the
  step across the loop point is within the loop's ordinary sample-to-sample
  range.
- **Run result: NOT VERIFIED** — how any of it sounds. This machine has no
  speakers. Checked by measurement only: shape, brightness, balance, and for
  the cries that each is a voiced sound (at least 80% of it periodic) rather
  than breath.
