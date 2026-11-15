# Evidence: figures, fighting, the lived-in city, more sounds

Owner's request (2026-11-15): better graphics for the characters, their
faces, armour and the environment; a better fighting system; more realistic
sounds. Captured here with software rendering (no GPU), so the pictures show
form and layout, not speed. Nothing was heard: no audio device.

| File | What it shows |
|---|---|
| `01-figures-before-after.png` | The same line-up before (boxes and faceted lathes, faceless) and after (sculpted bodies, faces, armour, dappled ox-hide shields) |
| `02-faces.png` | Close-ups: boar's-tusk helmet over a bearded face, bronze helmet with cheek pieces and nasal, a veiled woman, a young man with a headband, Priam's white beard, a profile |
| `03-shields-front-and-back.png` | Shields solid from in front and behind (a facing bug, found by looking, now fixed) |
| `04-plain-and-fight.png` | Hector's view at the oak: grass, scrub and stones on the plain, an ally in scale armour |
| `05-city-clutter.png` | The town: washing on the roofs, woodpiles and jars at the house fronts, a stall in the square |
| `06-phone-fight.png` | Phone layout in battle, a Trojan close by: face, beard, pointed helmet, studded leather |
| `07-night-sword.png` | The night of the horse with the new sword in hand |
| `08-new-sounds.png` | Waveform and spectrum of the parry scrape, an armed footfall and two effort shouts |

## Run results

- **Run result: OBSERVED**: faces, helmets, armour and shields as listed, `01`-`03`, `06`.
- **Run result: OBSERVED**: cost held down. A figure is about 13,000 triangles up close; generated levels of detail bring the line-up of 19 seen from 14 m from 864,000 triangles to 240,000; sharing two materials per figure cut draw calls by 40%. The scattered clutter is batched per 64 m tile: the first attempt drew 4.3 million triangles a frame in the town, the tiled one 1.6 million.
- **Run result: OBSERVED**: no building mid-fight. A mission sculpts its cast behind its loading screen: 2.3 s natively, 2.5 s in headless Chromium.
- **Run result: OBSERVED**: the new moves happen in real fights. With the scripted player: three-blow combos, shield shoves and ripostes (gate mission: 19 combos, 5 shoves, 2 ripostes); the new sounds fire (armed footfalls, effort shouts). The scripted player only taps Strike, so heavy blows and parries are covered by the rule tests and by the touch test that holds STRIKE.
- **Run result: NOT VERIFIED**: feel of the fighting (timing of the parry window, weight of the hit stop), frame rate on a phone, the sound of anything.

## Automated checks

- 83 tests: six new rule tests (heavy blow threshold, combo steps, combo damage and speed, heavy blow costs, riposte, guard outcomes) and a touch test that a held STRIKE throws a heavy blow on release.
- Both missions finished by the scripted player in desktop, phone and browser modes.
