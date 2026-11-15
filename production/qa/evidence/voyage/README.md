# Evidence: the voyage home (the Cyclops, the Sirens)

Two sea levels after *Odyssey* 9 and 12, on a shared sailing system
(`src/sea/`). Captured 2026-11-15 on the Linux engine (Forward+, software
Vulkan) at 1280 x 720, and in headless Chromium for the web build.

| Shot | What it shows |
|---|---|
| `01-menu-voyage-desktop.jpg` | The title screen's second page, THE VOYAGE HOME (`--menu=voyage`) |
| `02-menu-voyage-phone.jpg` | The same on the phone layout (`--mobile --phone`); the first page with its new entry still fits a short screen |
| `03-cyclops-at-sea.jpg` | The opening: at the steering oar, the rowers facing aft, the sail lit through from behind |
| `04-cyclops-shore-and-cave.jpg` | Ashore below the cave; the cliffs in face-aligned limestone (no smearing from the ground projection) |
| `05-cyclops-giant-in-doorway.jpg` | Polyphemus coming home at evening |
| `06-cyclops-giant-asleep.jpg` | The giant asleep, drunk, with the lambs in their folds |
| `07-cyclops-escape.jpg` | Rowing out of the bay |
| `08-ship-from-outside.jpg` | The ship: black hull, red bows, ten oars a side, oarsmen seated |
| `09-sirens-song.jpg` | Bound to the mast; THE SONG meter; the Sirens' meadow |
| `10-strait-scylla-cliff.jpg` | The strait: Scylla's cliff and cave mouth |
| `11-web-build-cyclops.jpg` | The packed Artifact page in Chromium, the Cyclops started from the menu |

## Runs

| Check | Result |
|---|---|
| `--mission=cyclops --bot --god` | MISSION COMPLETE, 530 s, no script errors |
| `--mission=sirens --bot --god` | MISSION COMPLETE, 548 s, no script errors |
| Both with `--mobile --phone` and `--web` | See `design/game-brief.md`, *Verification* |
| Web package in Chromium | Boots, opens the voyage page, starts the Cyclops |

## Fixed on the way

- **The bot could not enter the cave.** The door stone was part of the baked
  walkable area, so the map had no way through the doorway. It is now left
  out of the bake (it moves), and when open it rolls clear of the doorway.
- **The bot could not climb to the cave on phones.** The coarser phone terrain
  left a step too steep at a terrace edge. Ground the player climbs now keeps
  full detail on phones (`Island.walked`).
- **Twelve men stayed twelve.** Phones thin crowds; the twelve companions
  Homer names are no longer thinned (`spawn_group(..., exact)`).
- **The wine marker** pointed into the seated giant; it now marks where to
  stand and hold up the bowl.
- **The web package** grew past the 16 MB file limit with the new audio. The
  game data now ships in two parts that the page joins.

## Not verified

How the new music, ambiences and voices sound (no audio device here); frame
rate on a real phone.
