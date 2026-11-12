# Evidence: mobile

Captured on 2026-11-12 from the desktop engine running in mobile mode
(`--mobile`) with Godot's **Mobile** renderer (`--rendering-method mobile`) on
software Vulkan, at a phone's screen shape. No phone or tablet was available:
nothing here was seen on a real device.

```
godot --path . --windowed --resolution 1280x576 --rendering-method mobile -- --mobile --mission=gate --autoplay --stop=battle --shot=/abs/out.png
```

| File | What it shows |
|---|---|
| `01-menu-phone.png` | Title screen at 1.3x text scale: all five entries inside the frame, quotation moved to the lower right |
| `02-city-touch-controls.png` | Walk the City: thumb-stick, STRIKE / SHIELD / THROW / JUMP / CROUCH / ARMS, pause and READ; health under the objective, weapon line top right |
| `03-battle-touch-controls.png` | Battle at the oak: touch-worded hint ("Hold SHIELD..."), speech at the top clear of the buttons |
| `04-night-touch-controls.png` | Night on the citadel: watch meter, speech, torchlit porch; THROW hidden while the sword is in hand |
| `05-dialogue-phone.png` | Andromache: stick and fighting buttons hidden while Hector is held in talk |

## Run results

- **Run result: OBSERVED** — touch controls drawn in place, none overlapping the HUD text — `02`, `03`, `04`.
- **Run result: OBSERVED** — speech sits at the top on mobile, clear of the right-hand buttons — `03`, `04`, `05`.
- **Run result: OBSERVED** — menu fits a phone screen — `01`.
- **Run result: NOT VERIFIED** — everything on a real device: touch feel, frame rate, heat and battery, notches, the Android back gesture, sound.

## What the automated checks cover

- 8 touch tests (`tests/integration/touch_controls_test.gd`): stick walks and runs, a drag turns the view, a drag never strikes, STRIKE / SHIELD / CROUCH behave, no button off screen or overlapping another.
- Both missions finished in mobile mode by the scripted player (`--bot --god --mobile`).
- The debug APK was built, its signature verified, and a mission finished from the files packed inside it, run by the Linux engine. That proves the package is complete. It does not prove it runs on a phone.

## Defects found by looking, now fixed

- Tree leaves rendered pure black under the Mobile renderer (the generated leaf texture's colour channels read as black there). Leaves now take outline and shading from its alpha channel.
- The menu quotation covered QUIT on a short screen.
- Speech ran under the right-hand buttons.
