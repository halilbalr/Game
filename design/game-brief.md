# The Odyssey — Game Brief

*Design record for the project at `modes.workflow: minimal`. This file replaces
per-system GDDs; see `.claude/docs/workflow-modes.md`.*

## One line

A first-person telling of the siege of Troy, after Homer: fight as an Achaean
attacker or a Trojan defender in a Late Bronze Age city rebuilt from the
excavations at Hisarlik.

## Pillars

1. **Homer's story, told from inside it.** Missions are episodes from the
   *Iliad*, the *Odyssey* and the Epic Cycle, played by the hero who lived
   them, with the people who were there.
2. **A real Bronze Age.** The city follows Troy VI/VIIa as excavated; arms and
   armour are Late Bronze Age Aegean and Anatolian. No iron swords, no
   hoplites, no catapults, no cavalry.
3. **War as the poem shows it.** Close, bloody and personal. Spears first,
   swords when the spear is gone, shields that matter.
4. **Gods felt, not seen.** Omens, voices and luck. The world stays grounded.

## Scope of this slice

| Mode | Hero | Source | Summary |
|---|---|---|---|
| **The Wooden Horse** (attacker) | Odysseus | *Odyssey* 4.271-289, 8.492-520; *Little Iliad*; *Sack of Ilium* | Keep the men silent inside the horse while Helen calls to them, climb down at night, slip through the sleeping city, kill the gate watch, unbar the Scaean Gate, then fight with Menelaus to the house of Deiphobus. |
| **The Scaean Gate** (defender) | Hector | *Iliad* 6.237-529, 16.684-867 | Part from Andromache and the child at the gate tower, lead the sortie, hold the ground before the gate against the Achaean assault, and meet Patroclus in Achilles' armour when he storms the wall. |
| **Walk the City** | — | Excavation record | Free exploration of Troy by day with a chronicle of what is known about each place. |
| **The Cyclops** (the voyage home) | Odysseus | *Odyssey* 9.105-566 | Row to the land of the Cyclopes, climb to the cave with twelve men, be shut in by Polyphemus, cut and harden a stake from his club, make him drunk and give your name as Nobody, blind him in his sleep, get out under the rams, and row away under the boulders he throws. |
| **The Sirens** (the voyage home) | Odysseus | *Odyssey* 12.37-259 | Stop the crew's ears with wax, be bound to the mast and resist the song as the ship passes the Sirens' meadow, then take the steering oar through the strait between Charybdis and Scylla, who takes six men from the benches. |

Later missions (roadmap, not built): the duel of Paris and Menelaus, Diomedes'
day, the night raid on Rhesus, the fight at the ships, Achilles and Hector,
Priam's ransom.

## The voyage home

Added after the Troy slice: two episodes from Odysseus' wanderings, played at
sea. They share one sailing system (`src/sea/`).

- **The ship** is a twenty-oared black ship of the Late Bronze Age: about
  22 m, pitch-black hull with red bows and an eye, one square sail on a
  lowering mast, a steering oar at the stern, ten oars a side. The player
  stands at the stern and steers (move forward to row harder, left and right
  to turn), or is placed by the mast. The ship rides the same waves the sea
  shader draws, rolls and pitches with them, and stops on rock.
- **The sea** is a sum of four long waves, computed both in the shader and in
  `Sea.height()`, so ships and thrown rocks meet the water where it is drawn.
  Charybdis is a funnel sunk into that surface and a current that draws the
  ship in.
- **Islands** are height functions with levelled places for a beach or a cave
  floor, walkable and solid. The cave of Polyphemus is a separate rock shell
  with a door stone that rolls aside.
- **Gods felt, not seen** holds at sea: the Sirens are a song and a meadow
  with heaps of bones, never shown. Scylla is shown only as Homer gives her:
  six long necks out of a cave high in the cliff, each with a head and three
  rows of teeth.
- **The Cyclops** is the one giant in the game: a man's figure at three times
  scale with a single eye, dressed as a herdsman.
- The song pulls the view toward the island (the meter THE SONG fills while
  the player looks at it). If it fills, Odysseus strains at the ropes and the
  crew tie him tighter: it slows the passage, it does not end the mission.
- Defeats: the ship drawn under by Charybdis, or broken by a boulder.
- **Hands on the work.** Whatever Odysseus does, the player sees his hands
  doing it (`Viewmodel.act`): the tiller at the helm, rope at his wrists at
  the mast (two of the crew bind him while the story is told), the stake in
  the fire and in the eye, the bowl raised to the giant, fists in the ram's
  fleece. Each oar is laid from its oarlock through its rower's two hands.
- **The sea, nearer the real thing.** A baked map of the sea floor turns the
  shallows turquoise and breaks surf at the waterline; the islands carry
  holm oak, olive, fig, maquis and boulders; spray flies off the bow; drops
  of water land on the view (`LensWater`).
- **Music.** A breathy wooden flute over drones and frame drums, original,
  in the manner of a modern film score for the Odyssey.

## The city

Source: Blegen's and Korfmann's excavations of Troy VI (c. 1750-1300 BC) and
VIIa (c. 1300-1180 BC), the level most often identified with Homer's war.

- **Citadel (Pergamos)**: an oval about 200 m by 160 m, close to true scale.
  Battered limestone ashlar walls with the vertical offsets every ten metres
  that are peculiar to Troy VI, under a mudbrick breastwork. South Gate (VI T)
  with Tower VI i and the row of stelae; East Gate (VI S) entered behind an
  overlapping curtain; West Gate (VI U) walled up, as it was in VIIa;
  North-East Bastion (VI g) over the cistern; Tower VI h.
- **Inside**: a ring of large freestanding terrace houses (megara) on rising
  ground, with small VIIa houses and sunken storage jars crowded against the
  wall. The summit was destroyed by later builders, so Priam's palace, the
  temple of Athena and the houses of Hector and Paris are reconstructions that
  follow Homer's placement (*Iliad* 6.242-250, 6.297, 6.313-317).
- **Lower town**: mudbrick houses on stone footings along streets leading to
  the gates, enclosed by a wall with a rock-cut ditch in front. The ditch is
  excavated fact. The wall and the placing of the Scaean and Dardanian Gates
  on it are conjecture, and the town is compressed to about a quarter of its
  true area for play.
- **Outside**: the plain of Scamander, the oak before the Scaean Gate, the wild
  fig, the washing troughs by the springs, the barrow of Ilus.

`src/world/troy_layout.gd` is the single source for every position.

## Arms and armour

Values live in `assets/data/weapons.json`; this table is the intent.

| Weapon | Homeric name | Basis | Role |
|---|---|---|---|
| Ash thrusting spear | *dory*, *enchos* | Bronze socketed heads, Mycenae and Troy | Primary. Long reach, can be thrown. |
| Bronze cut-and-thrust sword | *xiphos*, *phasganon* | Naue II type, c. 1200 BC | Sidearm. Faster, shorter. |
| Bronze dagger | *machaira* | Shaft-grave and later daggers | Silent kills from behind. |
| Javelin | *akon* | — | Thrown only. |

Shields: ox-hide round shield with bronze boss (*aspis*), tower shield
(*sakos*, Ajax). Helmets: boar's-tusk helmet (worn by Odysseus on the night
raid, *Iliad* 10.261-265), bronze helmet with horsehair crest. Body armour:
bronze cuirass, linen corslet, bronze greaves for the "well-greaved Achaeans".

## Core rules

- **Health** regenerates slowly out of combat. **Stamina** pays for sprinting,
  striking and holding a block.
- **Melee**: a strike has a wind-up, a hit moment and a recovery. A tapped
  Strike is a light blow; light blows that land inside a short window chain
  into a combo of three (each faster, the last harder). A held Strike is a
  heavy blow: slower, costlier, harder, and it breaks a guard. A shield
  raised within the parry window turns a blow aside and leaves the attacker
  reeling; a blow on a reeling man is a riposte. Strike with the shield up is
  a shove (stagger and push, no wound). Jump while stepping aside or back is
  a dodge with a moment of grace. Blows knock men back and freeze the world
  for an instant (hit stop). Soldiers wind up heavy blows of their own, more
  often the more skilled they are. Hits to the head do more; armour reduces
  body hits. The rules are pure functions in `src/combat/combat.gd`
  (`is_heavy`, `combo_step`, `blow`, `guard`), unit-tested.
- **Aim assist** (option, on by default; numbers in `aim_assist` of
  `tuning.json`): within 7 m and a 26-degree cone, measured side to side,
  the view eases toward the enemy nearest the crosshair, at full rate while
  the player moves or looks and at 30% when still (touch 2.4, gamepad 2.0,
  mouse 0.9 of the error per second, at most 1.1 rad/s). Look slows to 65%
  (touch, gamepad) or 85% (mouse) while the crosshair is on a man. A blow
  turns up to 12 degrees onto a man within reach, spread over the wind-up. A
  thrown spear bends up to 3.5 degrees toward a man near the crosshair,
  leading him if he runs. Picking and easing are `Combat.assist_pick` and
  `Combat.assist_turn`; the scripted test player does without it.
- **Throwing**: a held spear can be thrown; spears lying on the field can be
  picked up.
- **Stealth** (Wooden Horse): sentries see in a cone and hear running feet.
  Crouching cuts both. A sentry who becomes fully alert shouts; if he is not
  silenced within a few seconds the city wakes and the mission is lost.
- **Allies and enemies** fight each other without the player's help; no more
  than three enemies press the player at once.

All numbers are in `assets/data/tuning.json`.

## Figures

Every man and woman is sculpted in code (`src/actors/figure_mesh.gd` on
`src/actors/sculpt.gd`): smooth surfaces with computed normals rather than
faceted boxes. Heads have a modelled face (brow, cheekbones, jaw, chin, a
separately sculpted nose and lips, eyeballs with irises and lids, ears),
hair that grows from a hairline, and beards. Helmets sit on the brow with
cheek pieces, nasal and neck guard: boar's tusk rows, bronze with a
horsehair crest, the pointed Anatolian helmet with its plume, leather caps.
Armour follows the finds: the Dendra-style bronze corslet with shoulder
pieces and collar, quilted linen, studded leather, scale. Shields are
dappled ox-hide with stitching, rim, rivets and boss.

Two materials draw all of it (`figure.gdshader`, `metal.gdshader`); what a
surface is made of rides in its vertex alpha, so a figure costs a few draw
calls. Each part carries generated levels of detail, and parts are shared
between figures whose looks agree on what that part depends on. A mission
sculpts its whole cast behind its loading screen (about 2.5 s), so nothing
is built mid-fight.

## The lived-in city

`src/world/clutter.gd` scatters grass, scrub and stones over the plain;
baskets, jars, benches, woodpiles, ladders and weeds before the houses;
washing on the flat roofs; stalls and carts in the square. Each kind is one
mesh drawn many times, batched per 64 m tile so distant tiles drop out.

## Tone and content

Blood on hit, on the ground and on the screen edge when wounded; bodies stay
where they fall. Blood can be switched off in the options. No dismemberment.

## Text

Dialogue is written for the game, following Homer closely. Direct quotations
are from Samuel Butler's prose translations (1898, 1900), which are in the
public domain, and are marked as quotations in the mission data.

## Technology

Godot 4.6, GDScript, Forward+ renderer, Jolt physics. All geometry, textures
and sound are generated in code; the repository contains no imported art.

## Mobile

One project serves desktop and mobile. `Game.mobile` is true on Android and
iOS (or with `--mobile` on a desktop) and switches on:

- **Touch controls** (`src/ui/touch_controls.gd`): a thumb-stick that appears
  under the left thumb, drag-to-look on the right, buttons for the fighting
  hand. They press the same input actions as the keyboard, so the player code
  is unchanged.
- **A lighter graphics tier**: Godot's Mobile renderer; no ambient occlusion
  or volumetric fog; a sky drawn once; terrain and city cut into 48 m pieces
  because the Mobile renderer lights each mesh with at most eight lamps. The
  Graphics option picks a row of `Game.LITE_TIERS`: the share of the screen's
  pixels given to the 3D view (0.5 / 0.67 / 0.85; the interface is always at
  full resolution), shader detail (the bump pass and full noise from Medium
  up), shadow reach, glow, torch range and crowd size (60 / 75 / 90%). Medium
  is the default.
- **Adaptive resolution**: `Game._process` watches the frame rate and scales
  the 3D resolution down under 26 fps and back up over 52, between half and
  all of the chosen tier. Nobody has measured a phone, so the game measures
  itself.
- **Layout**: on a tablet, text at 1.3x. On a phone (`Game.phone`: a screen
  under 3.7 inches on its short side, or `--phone`) the interface is drawn at
  1.7x with running text a quarter larger again, the touch buttons take their
  own closer-set positions (`TouchControls.PHONE_OFFSETS`, none under 10 mm
  across), speech sits at the top and notices between the thumbs, and the
  option panels scroll.

## Web

`Game.web` is true in a browser (or with `--web` on a desktop). The web build
is single-threaded WebAssembly on the Compatibility (WebGL 2) renderer and
shares the lighter graphics tier with mobile (`Game.lite`). Browser-specific
behaviour: the pointer is taken on a click, with a free-cursor fallback when
the page refuses; Ctrl is not a game key; the sound bank is built between
frames because there are no worker threads; torches far from the eye are put
out because that renderer draws only a few dozen lamps. `tools/web/` packs the
export as a claude.ai Artifact.

The Artifact page sizes the canvas itself, at the screen's own pixel density
(up to 3x, capped at 4.2 million pixels), so text is sharp on a phone. A
phone held upright gets the game turned a quarter: the page rotates the
canvas with CSS and the packer patches the one function in Godot's loader
that maps a touch to canvas coordinates. The page tells the game what it is
running on (`--mobile`, `--phone`).

## Sound

Three sources, all synthetic, none recorded:

- **Effects and ambience** are rendered by `tools/audio/make_sfx.py` at
  44.1 kHz: `assets/audio/sfx/<id>_<n>.ogg` with several variants of each
  (counts in `assets/audio/sfx/index.json`) and 24-second seamless loops in
  `assets/audio/ambience/`. A blow is layered from its parts: a punch, the
  crack of the point or the bite of the blade, the wet tail, a bronze ring
  when it meets a helmet or a shield boss. The ox-hide shield booms like a
  drum, a man falls knees first, then his body, then his gear. Swings are
  heard as the weapon comes through, not at the wind-up. Cries, grunts and
  the watch's shouts are spoken by the Kokoro model and driven into
  distortion; the feast is Kokoro voices talking over each other behind
  timber. Impacts are tuned for phone speakers: their weight sits in
  overtones above 150 Hz rather than in a fundamental a phone cannot play.
  `Sfx.strike` picks the sound of a blow from what it met (shield, stealth,
  cut, thrust, head); each play takes a variant at random, never the last one,
  with a small change of pitch and level. Soldiers' footfalls carry the rattle
  of their gear; men grunt as they put weight behind a blow; a parry is a
  scrape of bronze on bronze. Far sounds are muffled by distance on desktop
  and Android (a browser's audio engine plays them unfiltered).
- **Music** is composed and rendered by `tools/audio/make_music.py` into five
  looping tracks (`assets/audio/music/`): `theme` (title screen), `battle`,
  `night` (the horse, the sleeping city), `lament` (Andromache, endings,
  defeat) and `lyre` (Walk the City). D minor leaning on the lowered second, the nearest modern scale to
  the Greek Dorian. Mixed for phone speakers: little below 150 Hz.
- **Voices** are rendered by `tools/audio/make_voices.py` with the Kokoro
  text-to-speech model, one file per line of the mission data
  (`assets/audio/voice/<mission>/<key>.ogg`) and one per narrated text. Each
  speaker has a cast voice; gods get a long hall, voices outside the horse
  are muffled. Homeric names are spelled out in phonemes because the model's
  dictionary gets most of them wrong.

`Sfx.speak` plays a line and returns its length, which sets how long the
subtitle stays. Music and ambience duck 8 dB under speech.

Nothing is synthesised while the game runs. (Until the phone fixes, effects
were built at start-up; in a browser that took about 25 seconds of the main
thread, in slices that made the first half-minute of play stutter.)

## Touch look and smooth movement

A drag's movement is measured by `TouchControls` from each finger's last
position, never from the engine's `relative`: in a browser Godot measures that
from whichever finger came first in the previous touch event, so with a thumb
on the stick and another looking it was off by the distance between the
thumbs, and the view jumped round by up to a few hundred degrees.

The body moves in fixed physics steps (60 a second) while a phone draws at its
own uneven rate. `Player._process` draws the eye between the body's last two
steps, so walking does not stutter against the smoothly turning view.

## Scenes and skipping

A mission script brackets each stretch of story with `scene_begin()` and
`scene_end()`. Inside one, the Skip action (Enter, right stick, the SKIP
button) ends every line, wait and title card until the scene closes. Anything
the player must do stays outside a scene, so a skip always lands on the next
thing to do. Title cards are narrated and are scenes too.

## Verification

| Check | How | State |
|---|---|---|
| Rules and formulas (combat moves included), touch controls (two-thumb look, tap and hold Strike), phone button layout, every sound the scripts ask for exists, aim assist, the sea surface, islands and cave doorway, oars through the rowers' hands | 99 tests, `tests/run_tests.gd` | Pass |
| Missions in mobile and phone mode | `--mission=<id> --bot --god --mobile --phone` | Pass |
| Android package is complete | Debug APK built and signed; a mission finished from its contents on the Linux engine | Pass |
| The app builds on a real phone or tablet | — | Not verified |
| Web build boots and takes input | Exported build and the packed Artifact page in headless Chromium | Pass |
| Phone page: landscape turn, 3x canvas, touches mapped through the turn, SKIP | Chromium emulating a 440 x 956 touch screen | Pass |
| The published Artifact inside claude.ai | The owner's screenshot from an iPhone (first version) | Runs; the phone upgrade itself not yet seen on a device |
| Voices and music play; a heard line is released from browser memory | Instrumented page in Chromium (streams registered, started, dropped) | Pass |
| How the voices and music sound | Listening | Not verified |
| Mission scripts reach their end | `--mission=<id> --autoplay` | Pass |
| Player combat through real input | `--scene=arena --autoplay --bot` | Pass |
| Whole missions with real walking, fighting and use | `--mission=<id> --bot --god` (`--noalarm` for the horse) | Pass: both reach their ending |
| The voyage: rowing, steering, climbing, using, whole missions | `--mission=cyclops` and `--mission=sirens` with `--bot --god`, each also with `--mobile --phone` and with `--web` | Pass: all six runs reach the ending, no script errors |
| Screen transitions | `--tour --autoplay` | Pass |
| Layout, legibility, presence | Screenshots in `production/qa/evidence/vertical-slice/` | Looked at |
| Frame rate on real hardware | — | Not verified |
| Feel of combat, difficulty | Human play | Not verified |
| Sound | Listening | Not verified |

The slice was built on a machine with no GPU and no audio device. The last
three rows need a person at a real computer.

The scripted player is invulnerable and does not sneak, so it proves that each
mission can be finished, not that it is fair or fun. Sneaking past the watch
is covered only by the perception tests and by confirming that being seen ends
the mission.

## Out of scope for the slice

Chariots, archery for the player, ship combat, multiplayer, saving mid-mission.
