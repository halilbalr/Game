<!-- PROTOTYPE - NOT FOR PRODUCTION -->
<!-- Question: Is a first-person "escape the party" chase against a meme villain fun across five short nights? -->
<!-- Date: 2026-10-22 -->

# Five Nights at Diddy's

A parody first-person horror game. You wake up at the afterparty in Diddy's mansion.
The front door is locked and your stuff is scattered around the house. Find it and get
out, or survive until 6 AM. Diddy hunts you the whole time. If he catches you, you get
diddled.

![Menu](screenshots/01-menu.jpg)

## Hypothesis

A short, readable chase loop (scavenge, hear him coming, break line of sight, drop baby
oil, run for the door) is fun for five escalating nights. Two exits keep it from becoming
a pure hiding game: escape early, or outlast the clock.

## How to run

Open `prototype.html` in a desktop or mobile browser. It's one self-contained file, with no
build step and no server. It needs an internet connection the first time, because Three.js
(r160, jsDelivr) and the fonts (Google Fonts) load from CDNs.

| Action | Keyboard / mouse | Phone |
|---|---|---|
| Move / look | WASD + mouse | Left thumb / right thumb |
| Sprint | Shift | RUN (toggle) |
| Flashlight | F | LIGHT |
| Drop baby oil | Space | OIL |
| CCTV map | C | CAM |
| Pause | Esc | II |

## What's in it

- **The mansion:** 11 rooms plus hallways on a 33 × 24 grid of 3 m cells (`MAP` in the
  script): guest bedroom, library, master suite, kitchen, baby oil storage, ballroom, indoor
  pool, VIP lounge, home theater, grand foyer and wine cellar. Every texture is drawn
  procedurally on canvas, so the game ships no image files.
- **Diddy:** a hand-drawn caricature (white suit, gold chains, shades, a bottle of baby oil)
  shown as a camera-facing billboard, Nextbot style. He runs on a state machine
  (dance → patrol → search → alert → chase → stunned) with A\* pathfinding on a 1 m nav
  grid. He sees you (vision cone, walls block sight, the flashlight extends his range) and
  hears you sprint.
- **His lines:** "Let me take you out shopping, playa!" and "You deserve it, daddy!" while
  chasing. "Ain't no party like a Diddy party!" when he catches you. They're spoken with the
  browser's speech engine and also shown as subtitles.
- **Systems:** stamina, a battery shared by the flashlight and the CCTV map, baby oil
  puddles that make him slip, and a final-item trigger that sends him straight at you.
- **Atmosphere:** party music synthesized with WebAudio (it gets muffled the further you are
  from the ballroom), positional footsteps, a heartbeat, bloom, film grain and red
  danger edges.
- **Custom face:** Settings → "Use a photo" swaps the drawn face for any picture you pick.
  The photo stays in your browser.

All tuning lives in `TUNING` and `NIGHTS` at the top of the script. Each night is faster,
sharper-eyed, darker and longer than the last, and asks for more items.

## Status

In progress. Built and machine-tested; it has not been playtested by a person yet.

## Verification so far

These ran headless in Chromium (SwiftShader) with no console errors:

- Every room, the player spawn and the exit are reachable on Diddy's nav grid.
- 90 s on night 3: he leaves the party after the grace period and patrols without
  getting stuck.
- A visible player is spotted and caught in about 4 s (alert, then chase, then jumpscare).
- Baby oil makes him slip and stay down for the night's stun time, then he resumes the hunt.
- Surviving to 6 AM and escaping with every item both win the night and unlock the next one.
- Screenshots in `screenshots/` cover desktop and phone (390 × 844) layouts.

## Findings

Pending a real playtest. Things to watch:

- Is night 1 forgiving enough? (Diddy chases at 4.4 m/s; you walk at 3.7 and sprint at 6.4.)
- Does the CCTV map make hiding too easy, or is the battery cost enough?
- Phone performance on the Low graphics preset.

## Known limits

- Software rendering (no GPU) runs at 1–3 fps. Real GPUs are fine.
- Voices depend on the browser's installed speech voices. Subtitles always show.
