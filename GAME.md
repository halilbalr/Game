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

## Options

Mouse sensitivity, field of view, volume, graphics quality, blood on or off,
inverted look, head bob, fullscreen. **Blood** removes the spray, the pools
and the red at the screen edge.

## Known limits

- People are built from simple shapes and animated in code. They read as
  figures, not as portraits.
- All sound is synthesised. There is no recorded speech; lines are shown as
  text.
- No saving inside a mission. Each takes ten to fifteen minutes.
- Not yet in: chariots, archery, the other episodes of the war.

## For developers

```
godot --headless --path . --import                              # once after cloning
godot --headless --path . -s res://tests/run_tests.gd           # 64 tests
godot --headless --path . --fixed-fps 60 -- --mission=horse --autoplay   # script plays itself; exit 0 on completion
godot --headless --path . --fixed-fps 60 -- --mission=gate --autoplay
godot --headless --path . --fixed-fps 60 -- --scene=arena --autoplay --bot   # scripted player through real input
godot --headless --path . --fixed-fps 60 -- --tour --autoplay   # menu, city, menu, mission
```

Design record: `design/game-brief.md`. Where everything stands:
`src/world/troy_layout.gd`. Numbers: `assets/data/`. Screenshots:
`production/qa/evidence/vertical-slice/`.
