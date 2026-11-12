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

Later missions (roadmap, not built): the duel of Paris and Menelaus, Diomedes'
day, the night raid on Rhesus, the fight at the ships, Achilles and Hector,
Priam's ransom.

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
- **Melee**: a strike has a wind-up, a hit moment and a recovery. A raised
  shield stops blows from the front at a stamina cost. Hits to the head do
  more; armour reduces body hits.
- **Throwing**: a held spear can be thrown; spears lying on the field can be
  picked up.
- **Stealth** (Wooden Horse): sentries see in a cone and hear running feet.
  Crouching cuts both. A sentry who becomes fully alert shouts; if he is not
  silenced within a few seconds the city wakes and the mission is lost.
- **Allies and enemies** fight each other without the player's help; no more
  than three enemies press the player at once.

All numbers are in `assets/data/tuning.json`.

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
- **A lighter graphics tier**: Godot's Mobile renderer; shaders without the
  bump pass and with half the noise octaves; no ambient occlusion, volumetric
  fog or glow; a short two-split sun shadow; a sky drawn once; terrain and
  city cut into 48 m pieces because the Mobile renderer lights each mesh with
  at most eight lamps.
- **Smaller battles**: groups are fielded at 60% (`Game.crowd_scale`).
- **Layout**: text at 1.3x, health and speech moved up out from under the
  thumbs, hints reworded for touch.

## Web

`Game.web` is true in a browser (or with `--web` on a desktop). The web build
is single-threaded WebAssembly on the Compatibility (WebGL 2) renderer and
shares the lighter graphics tier with mobile (`Game.lite`). Browser-specific
behaviour: the pointer is taken on a click, with a free-cursor fallback when
the page refuses; Ctrl is not a game key; the sound bank is built between
frames because there are no worker threads; torches far from the eye are put
out because that renderer draws only a few dozen lamps. `tools/web/` packs the
export as a claude.ai Artifact.

## Sound

Synthesised at start-up on a worker thread (`src/core/sfx.gd`): bronze as
inharmonic partials, voices as a pulse train through two formant filters, a
plucked-string lyre in the Greek Dorian mode, and looping ambience for night,
day, the feast heard through the planks, battle and the sack.

## Verification

| Check | How | State |
|---|---|---|
| Rules and formulas, touch controls | 72 tests, `tests/run_tests.gd` | Pass |
| Missions in mobile mode | `--mission=<id> --bot --god --mobile` | Pass |
| Android package is complete | Debug APK built and signed; a mission finished from its contents on the Linux engine | Pass |
| Anything on a real phone or tablet | — | Not verified |
| Web build boots and takes input | Exported build and the packed Artifact page in headless Chromium | Pass |
| The published Artifact inside claude.ai | — | Not verified |
| Mission scripts reach their end | `--mission=<id> --autoplay` | Pass |
| Player combat through real input | `--scene=arena --autoplay --bot` | Pass |
| Whole missions with real walking, fighting and use | `--mission=<id> --bot --god` (`--noalarm` for the horse) | Pass: both reach their ending |
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
