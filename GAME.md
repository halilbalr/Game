# The Odyssey

A first-person telling of the siege of Troy, after Homer. Play an Achaean
attacker or a Trojan defender in a Late Bronze Age city rebuilt from the
excavations at Hisarlik.

This is a vertical slice: the whole city, two story missions and a free walk.
Everything in it (buildings, people, weapons, textures, sound) is generated in
code. There is no imported art.

## Play it

1. Install **Godot 4.6** (free): <https://godotengine.org/download>. Take the
   standard build, not the .NET one.
2. Open Godot, choose **Import**, and select `project.godot` in this folder.
3. Press **F5**.

The first launch takes a few seconds to build the city and its navigation
mesh. The navigation mesh is then cached, so later launches are quicker.

A desktop GPU that supports Vulkan (or Direct3D 12 on Windows) is needed.
If it runs slowly, set **Options > Graphics** to **Low**.

## On a phone or tablet

The quickest way onto a phone is the browser version: open the Artifact and
press Play (see *In a browser* below). **Hold the phone sideways.** If the
page stays upright, the game turns itself a quarter so it still fills the
long side of the screen.

The same project also builds as an app for Android and iOS. On a mobile
device it switches by itself to touch controls, larger text, slightly smaller
battles and a lighter renderer. The browser version has been seen running on
an iPhone; the app builds have not been run on a real device.

**Android, the quick way.** A debug build, `the-odyssey.apk` (33 MB, 64-bit
ARM, Android 7 or later), was made alongside this project. Copy it to the
phone, open it, and allow installing from that source when asked. It is not
kept in the repository.

**Android, building it yourself.** In Godot: *Editor > Manage Export
Templates > Download and Install*, then set the Android SDK and Java paths
under *Editor Settings > Export > Android*
([Godot's guide](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html)).
Then *Project > Export*, choose the **Android** preset that ships with the
project, and *Export Project*. With a phone plugged in, the one-click deploy
button in the top bar installs and runs it.

**iPhone and iPad.** This needs a Mac with Xcode and an Apple developer
account, so no build is supplied. In Godot on the Mac: *Project > Export >
Add > iOS*, enter your Team ID and a bundle identifier, export, then open the
Xcode project and run it on the device
([Godot's guide](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html)).

**Touch controls**

| | |
|---|---|
| Move | Left thumb, anywhere on the left half. Push the stick to its rim to run. |
| Look | Drag anywhere on the right. A thumb resting on STRIKE or SHIELD can still turn the view. |
| STRIKE | Tap. |
| SHIELD | Hold. |
| THROW | Tap. Shown while a spear is in hand. |
| ARMS | Next weapon. |
| CROUCH | Tap to crouch, tap again to stand. |
| SKIP | Shown during a scene. Passes over the rest of it. |
| JUMP | Tap. |
| USE | Appears only when there is something to use. Some things must be held. |
| READ | Walk the City only: the chronicle of the place you are standing in. |
| II | Pause. The Android back gesture pauses too. |

On a phone-sized screen the interface is drawn at 1.7 times its desk size,
running text a quarter larger again, and the buttons are at least a
centimetre across.

**Graphics on a phone.** The interface and text are always drawn at the
screen's full resolution. **Options > Graphics** sets the 3D picture:

| | 3D resolution | Stone and ground detail | Sun shadows | Glow | Soldiers |
|---|---|---|---|---|---|
| Low | half the screen's pixels each way | plain | 70 m | off | 60% |
| Medium (default) | two thirds | full bump and grain | 120 m | on | 75% |
| High | 85% | full | 180 m, four cascades | on | 90% |

The game also watches its own frame rate: under about 26 frames a second it
lowers the 3D resolution a step at a time (never below half of the chosen
level), and raises it again above 52. This game draws its stone, plaster and
ground with procedural shaders rather than stored textures, which is heavy
work for a phone, and how smoothly a given phone runs each level has not been
measured. If it is slow, choose **Low**.

To try the touch layout on a desktop, with the mouse standing in for a finger:

```
godot --path . -- --mobile
```

## In a browser

The game also exports for the web (WebAssembly and WebGL 2) and has been
published as a claude.ai Artifact. In a browser it uses the lighter graphics
tier, and on a phone browser the touch controls.

- Click the game to take control of the view. **Esc** frees the pointer,
  **P** pauses, **Enter** skips a scene.
- On a phone the page draws the game at the screen's own resolution (up to
  3x) and plays it in landscape whichever way the page is held.
- Crouch is **C** only (Ctrl+W would close the tab) and the chronicle is **R**.
- The first start takes up to half a minute.

To rebuild the web version and pack it as an Artifact:

```
godot --headless --path . --export-release "Web" builds/web/index.html
python3 tools/web/pack_artifact.py        # writes builds/artifact/
```

The engine is 38 MB of WebAssembly, more than an Artifact file may be, so the
packer gzips it, writes it as base64 text and the page unpacks it in the
browser. The packer also makes two small changes to Godot's loader script:
it maps touches correctly when the page has turned the game sideways, and it
lets the game release a spoken line from the browser's audio memory once it
has been heard.

## The three modes

| Mode | You are | What happens |
|---|---|---|
| **The Wooden Horse** | Odysseus, attacker | Keep the men silent inside the horse while Helen calls to them by their wives' names. Climb down at night. Go through the sleeping city without rousing the watch. Kill the guard at the Scaean Gate, lift the bar, and let the army in. Then fight with Menelaus to the house of Deiphobus. |
| **The Scaean Gate** | Hector, defender | Find Andromache and your son at the gate. Lead the sortie to the oak. Hold the ground against two Achaean attacks. Then the Myrmidons come, led by a man in the armour of Achilles. |
| **Walk the City** | Hector, at peace | Walk Troy by daylight. Near a place of note, press **Tab** to read what is known about it. |

## Controls

| | Keyboard and mouse | Gamepad |
|---|---|---|
| Move | W A S D | Left stick |
| Look | Mouse | Right stick |
| Strike | Left mouse | Right trigger |
| Raise shield | Right mouse (hold) | Left trigger |
| Throw spear | G or middle mouse | Right bumper |
| Change weapon | 1 2 3, wheel, or Q | Y |
| Use | E (some things must be held) | X |
| Run | Shift | Click left stick |
| Crouch | Ctrl or C | B |
| Jump | Space | A |
| Chronicle | Tab | Back |
| Skip a scene | Enter | Click right stick |
| Pause | Esc | Start |

## How fighting works

- The **spear** has the longest reach and hits hardest. It can be thrown. You
  carry two; spears lying on the field can be picked up.
- The **sword** is quicker and shorter. You draw it automatically when the
  last spear is gone.
- The **dagger** (Odysseus only) is for a man who has not seen you.
- A raised **shield** stops blows from the front and costs stamina. A blow on
  an exhausted arm drives through.
- Blows to the head do more. Bronze turns part of a blow to the body.
- Health comes back slowly when you are out of the fight.

On the night of the horse, a watchman sees in front of him and hears running
feet. Crouch to move quietly. If one sees you, you have a few seconds to
silence him before he rouses the city and the mission is lost.

## What is excavated and what is reconstructed

| Excavated | Reconstructed |
|---|---|
| The citadel's size and oval plan | The whole summit: palace, temple of Athena, houses of Hector and Paris. Later builders levelled it. These follow Homer's placement and the megaron plan of the houses below. |
| Battered limestone walls with vertical offsets every ten metres; mudbrick above | Height and form of the breastwork |
| South Gate with Tower VI i and the stelae; East Gate behind its overlapping curtain; the blocked West Gate; the North-East Bastion and its cistern | |
| Large freestanding terrace houses; small VIIa houses and sunken storage jars against the wall | Which house belonged to whom |
| A lower town, and its rock-cut ditch with a gateway gap | The lower-town wall, the position of the Scaean and Dardanian Gates on it, and the street plan. The town is also compressed to about a quarter of its true area. |
| Boar's-tusk helmets, bronze cuirasses and greaves, socketed spearheads, Naue II swords, ox-hide shields | Colours of cloth; which side wore what. Trojans are given Anatolian pointed helmets after the King's Gate relief at Hattusa. |

The plain, the camp and the shore are drawn much closer to the city than they
were.

## Text and sources

The missions follow *Iliad* 6.237-529 and 16.684-867, *Odyssey* 4.271-289 and
8.492-520, and the summaries of the *Little Iliad* and *Sack of Ilium*.
Dialogue was written for the game and keeps close to Homer. The one direct
quotation, on the title screen, is from Samuel Butler's translation of 1900,
which is in the public domain.

The gods do not appear. Athena and Apollo are heard, and what Homer gives to a
god's hand the game gives to mist, thunder and chance.

## Voices and music

Every line is spoken, and the introductions and endings are narrated. Hector,
Andromache, Menelaus, Helen and the rest each have their own voice; Athena
and Apollo speak from a long way off; Helen and Sinon are heard through the
planks of the horse. Subtitles stay on.

**The voices are synthetic.** They were generated ahead of time with the
Kokoro text-to-speech model and are not recordings of actors. The Greek names
were given their traditional English pronunciations by hand. They have not
been checked by ear: this project was built on a machine with no speakers.

Four pieces of music were written for the game and synthesised in code
(strings, horn, choir, a reed pipe, a lyre and skin drums): a march for the
title screen, a drum-driven piece for the fighting, a sparse one for the
night in the city, and a lament for partings and endings. Music drops under
speech.

Scenes can be skipped: **Enter**, the right stick, or the SKIP button on a
touch screen. A skip jumps to the next moment you have to do something.

To regenerate the audio (`pip install kokoro-onnx numpy scipy`, ffmpeg, and
the Kokoro model files):

```
python3 tools/audio/make_voices.py --model /path/to/kokoro
python3 tools/audio/make_music.py
```

## Options

Mouse sensitivity, field of view, volume, difficulty, graphics quality, blood
on or off, inverted look, head bob, fullscreen.

- **Difficulty** changes how much a blow hurts you: *Bard's tale* (about half),
  *Warrior* (the default), *Hero* (half as much again). Combat has only been
  tested by scripts, not by a person, so expect to adjust this.
- **Blood** removes the spray, the pools and the red at the screen edge.

## Licences

The game's own code and data are in this repository. It runs on
[Godot Engine](https://godotengine.org/license) (MIT licence), whose notice
must accompany any build that is passed on: the Artifact page carries it under
"Engine licence".

The two typefaces, Cinzel and Crimson Pro, are under the SIL Open Font Licence
1.1; the licence texts are beside them in `assets/fonts/`. The voice files
were generated with [Kokoro](https://github.com/hexgrad/kokoro) (Apache-2.0)
through [kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx) (MIT); the
model itself is not part of this repository.

## Known limits

- People are built from simple shapes and animated in code. They read as
  figures, not as portraits.
- Voices and music are synthetic and have not been heard by the person who
  built them. Effects are synthesised when the game starts.
- No saving inside a mission. Each takes ten to fifteen minutes.
- Not yet in: chariots, archery, the other episodes of the war.

## For developers

```
godot --headless --path . --import                              # once after cloning
godot --headless --path . -s res://tests/run_tests.gd           # 73 tests
godot --headless --path . --fixed-fps 60 -- --mission=horse --autoplay   # script plays itself; exit 0 on completion
godot --headless --path . --fixed-fps 60 -- --mission=gate --autoplay
godot --headless --path . --fixed-fps 60 -- --scene=arena --autoplay --bot   # scripted player through real input
godot --headless --path . --fixed-fps 60 -- --tour --autoplay   # menu, city, menu, mission
godot --headless --path . --fixed-fps 60 -- --mission=gate --bot --god              # whole mission, real walking and fighting
godot --headless --path . --fixed-fps 60 -- --mission=horse --bot --god --noalarm   # the same; the bot cannot sneak
godot --headless --path . --fixed-fps 60 -- --mission=gate --bot --god --mobile     # add --mobile for the touch tier, --phone as well for a phone-sized screen
godot --headless --path . --fixed-fps 60 -- --mission=gate --bot --god --verbose    # log each step of the mission script
godot --headless --path . --export-debug "Android" builds/the-odyssey.apk           # needs export templates and an Android SDK
```

`--bot` drives the player through the real input path: it walks the navigation
mesh to the objective, fights what it meets and holds Use. `--god` makes the
player invulnerable and `--noalarm` stops the watch from ending the mission.
`--autoplay` is the cheaper check: the script teleports and kills for itself,
which proves the story reaches its end but hides anything a walking player
would trip on. Three such bugs were found only by `--bot`.

Design record: `design/game-brief.md`. Where everything stands:
`src/world/troy_layout.gd`. Numbers: `assets/data/`. Screenshots:
`production/qa/evidence/vertical-slice/`.
