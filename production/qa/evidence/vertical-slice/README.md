# Evidence: vertical slice

Screenshots captured from the running game on 2026-11-12, Godot 4.6 stable,
Forward+ renderer on Mesa llvmpipe (software Vulkan) under Xvfb. They show
layout, presence, colour and legibility. They do not show frame rate, feel or
sound: the capture machine has no GPU and no audio device.

Reproduce any of them with the harness in `src/main.gd`, for example:

```
godot --path . --windowed --resolution 1280x720 -- --mission=gate --autoplay --stop=battle --shot=/abs/out.png
```

| File | What it shows | How it was reached |
|---|---|---|
| `01-main-menu.png` | Title, the three modes, the Butler quotation, the city at evening behind | default launch |
| `02-citadel-south-gate.png` | First-person view across the square to the South Gate and Tower VI i; spear in hand; HUD; chronicle prompt | `--mission=roam --at=0,0.2,120,0,0.06` |
| `03-city-overview.png` | Citadel, lower town in street rows, lower wall | `--mission=roam --cams=...` |
| `04-scaean-gate-from-plain.png` | The Scaean Gate and its two towers from the plain | `--mission=roam --cams=...` |
| `05-priams-court.png` | Priam's megaron with columns in antis, the chamber wings, temple and house either side | `--mission=roam --cams=...` |
| `06-achaean-ships.png` | Black ships drawn up on the shore, one red-bowed, the sea beyond | `--mission=roam --cams=...` |
| `07-inside-the-horse.png` | The compartment: planks, firelight through the chinks, a companion crouched | `--mission=horse --autoplay --stop=inside --quality=0` |
| `08-horse-on-the-citadel-night.png` | The horse on the court among torchlit halls; stealth meter reading UNSEEN; speech | `--mission=horse --autoplay --stop=exit --quality=0 --cams=...` |
| `09-inside-scaean-gate-night.png` | Night inside the Scaean Gate: barred door leaf, wall stair, objective marker | `--mission=horse --autoplay --stop=sack --quality=0` |
| `10-andromache.png` | Andromache at the gate, the watch behind her, speech text | `--mission=gate --autoplay --stop=andromache` |
| `11-battle-at-the-oak.png` | Trojan line under the oak, objective and hint text | `--mission=gate --autoplay --stop=battle` |
| `12-pause-and-options.png` | Pause panel, options and the controls list | `--mission=roam --pause` |
| `13-arms-and-armour.png` | Odysseus, Menelaus, Diomedes, Patroclus and others: boar's-tusk and crested helmets, cuirasses, greaves, ox-hide shields | `--scene=figures` |

## Run results

- **Run result: OBSERVED** — menu renders with all five entries inside the frame and legible at 720p — `01-main-menu.png`.
- **Run result: OBSERVED** — HUD bars, objective, weapon line and aim point present in first person; no clipping — `02-citadel-south-gate.png`.
- **Run result: OBSERVED** — pause, options and controls panels fit the frame — `12-pause-and-options.png`.
- **Run result: OBSERVED** — speech text wraps inside its box under a speaker name — `10-andromache.png`.
- **Run result: NOT VERIFIED** — the burning-city phase of The Wooden Horse was not captured at full fire. `09` was taken at the moment the gate opens, before the fires spread. The fire, smoke and sky-glow code runs without error in the automated play-through but has not been looked at.
- **Run result: NOT VERIFIED** — frame rate on real hardware, the feel of combat, and all sound. None can be judged on the capture machine.

## Play-through runs (no screenshots)

Headless, real walking, fighting and interaction, player invulnerable:

- `--mission=gate --bot --god`: MISSION COMPLETE after 336 s of game time, 15 kills.
- `--mission=horse --bot --god --noalarm`: MISSION COMPLETE after 377 s of game time, 21 kills.
- `--mission=horse --autoplay --stop=exit --bot --god` (alarm on, bot running): MISSION FAILED (THE CITY WAKES) after 60 s, as intended.

Bugs these runs found and that are now fixed: the player was set down beneath
the horse's sledge and could not move; Hector's mission started the player
inside a house beside the street; two script triggers began exactly at their
objective markers.
