# Halloween seasonal bezel

A themed bezel for the days around Halloween, used as a marketing moment. The bezel itself
stays the canvas: same size, styles and positions. Lottie animations play in and around it,
driven by the six things a key can do: volume up, volume down, mute, unmute, brightness up and
brightness down.

## Decisions

- **Season window:** October 28 to November 3 (three days either side of the 31st), in the
  user's own calendar. On by default; Preferences has a switch that turns seasonal bezels off
  completely, and a pop-up for the look (below), enabled while the switch is on.
- **Two looks, the user's pick** (`HalloweenLook`, default Harvest Moon). See [Look](#look).
- **No pumpkin for now.** Its full-colour artwork didn't fit either look, so brightness keeps
  the SF sun, drawn in the look's ink. `HalloweenScene.showsPumpkin` brings it back; the asset
  and `PumpkinGlyph` are still there.
- **Volume at 0 counts as mute.** The bezel already treats "muted" and "turned all the way down"
  the same (slashed speaker, empty bar), and the spider follows that.
- **The muted glyph stays `speaker.slash`**, with the web drawn over it.
- **Brightness up at 100% still bursts bats.** The level can't go higher, but the key press
  still counts as brightness up, so every press sends more bats out of the bezel. Volume down at
  0% stays silent and plays nothing extra.
- **The ghost says "BOO!" at 100% volume.**

## How triggers are found

Callers don't say what happened; they say what the level is now, as an `HUDReading`
(`.volume(level:muted:)`, `.brightness(level:)` or `.caption(symbol:text:)`). The HUD compares
each reading with the previous one of its kind and derives an `HUDTransition`.

This matters because the Touch Bar observer echoes ReBezel's own key changes back as a second
reading of the same level. Derived from the difference, that echo is "no change" and nothing
fires twice. Keys, the Touch Bar and the Preferences preview all go through the same path.

- Brightness is compared per display (Control+brightness changes an external one).
- A brightness key pressed at the end of the range passes the key's direction along with the
  reading, so it counts as up or down even though the level didn't move. The Touch Bar echo
  carries no key and stays "no change".
- "No change" brings a scene to the level without starting animations, but leaves the ones
  already running (bats in flight, the pumpkin turning scary) to finish.
- Differences under 0.001 are ignored, so a level read back slightly off from what was set is
  not a step. The smallest real step is 1/64.
- Going from silent (muted, or volume 0) to sound is **unmute**, even when it happened through
  volume up. The ghost and wisps then rise straight to the new level; no separate volume-up
  animation plays on top.

## Scene

```
AppDelegate ──HUDReading──▶ HUDWindowController ──(reading, transition)──▶ SeasonalScene (one per panel)
                               │ derives the transition                    ├─ glyph override (pumpkin / speaker + wisps)
                               │ larger panel while a season is active      ├─ GhostLayer       (clipped above the bezel)
                               └─ pauses the scene once faded out           ├─ SpiderWebLayer   (in front, over the glyph)
                                                                            └─ BatColony        (in front, whole panel)
```

While a season is active the panel's transparent margin grows from 40 to 240 points
(680×680), giving the bats room to fly out. Out of season the panel is exactly as before.

Back to front:

1. **Ghost**, in a clip view whose bottom edge is the bezel's top edge, so it rises from behind
   the bezel and never sits under (and gets lensed by) the glass.
2. **Bezel.** `HUDView.glyphOverride` replaces the SF Symbol with the scene's own view.
   `HUDView.backdrop` draws a graveyard silhouette (graves, a cross, a fence and a raven) along
   its bottom edge in the look's ink, for every reading. It is 16 pt wider than the bezel
   on each side and clipped to the bezel's edges; the level bar moves up to sit just above it.
3. **Spider and web**, over the glyph.
4. **Bats** (`BatColony`) over the whole panel: up to 16 hanging inside the bezel from its top
   edge at alternating heights, clear of the rounded corners, and the ones in flight, faded out before the panel edge. Roost and swarm
   are one class because bats move between them (taking off, landing).

The stages are layer-hosting views, so the scene owns their layer trees and can animate them
with Core Animation directly.

### Look

Everything in the scene (bats, graveyard, glyph, level bar, caption) is a flat silhouette in
one ink; only the bats' orange eyes keep their colour. The two looks differ in what the
silhouettes stand against. Colours are in `HalloweenPalette.swift`; changing the look rebuilds
the panels.

| | Silhouettes | Harvest Moon |
|---|---|---|
| Bezel background | The style's own (classic, Liquid Glass Regular or Clear) | A warm radial glow inside the bezel (`HUDView.backlight`), centred on the glyph: pale gold → amber → orange → ember at the corners, 94–84% opaque so the glass still shows through |
| Ink | Black, `#0A0A0A` | Warm near-black, `#170D0A` |
| Rim | White 70%, 2 pt, around every silhouette (`HUDView.rim`), so black shows on the dark classic bezel and dark wallpapers | None inside the bezel; bats get an amber rim (`#FFAD4C`, 2.5 pt), as if lit from behind |
| Empty bar | White 28% | White 30%, a slot the light shows through |

The glow is cut to the background's corner radius (`HUDView.cornerRadius`: 18 classic, 28
glass). It is a circular arc, so a hairline of plain glass can show at the continuous corners.

### Brightness

- **Glyph:** the standard sun, in the look's ink. (With `showsPumpkin` on, a jack-o'-lantern
  replaces it: animation progress = brightness, each change playing from the progress on screen
  to the new level, so up runs it forward and down runs it backward.)
- **Roost:** `ceil((1 − brightness) × 16)` bats, one per brightness key step, so every press
  down adds a bat. When the bezel appears they are already in place; only changes animate.
  Fine steps (Option+Shift, 1/64) add a bat on every fourth press.
- **Up:** bats in random roost spots take off, joined by 3–5 more from behind the bezel, flying
  outward in random directions. At most 24 bats are in the air at once.
- **Down:** bats fly in from random points at the panel edge to random free roost spots (never
  one already taken or with a bat on its way) and switch to the hanging animation.

Bats are pooled `LottieAnimationLayer`s playing one flapping loop, each moved along its own
random curved path by Core Animation with a random length, speed, size and start frame. A
Lottie file can't spawn or steer copies of itself. Each sits in a carrier `CALayer` anchored at
the bat's feet, so hanging bats hang and sway from them. Bat bodies are tinted the look's ink
with the look's rim (a shadow) so they show on dark wallpapers; the eyes stay orange.

`LottieAnimationLayer`, unlike `LottieAnimationView`, doesn't scale its drawing to its bounds: it
draws at the animation's natural size, y-down, centred on its own top-left corner. `Bat` in
`BatColony.swift` compensates (anchor at the top-left, a scale transform, flipped geometry);
use the same setup for any other bare Lottie layer.

Until a hanging-bat animation exists, a hanging bat is the flying bat upside down, frozen on
the frame with its wings raised.

### Volume

- **Bats:** the same roost as brightness, following the volume: `ceil((1 − volume) × 16)` bats,
  all 16 when silent (muted or at 0). Volume up sends bats off with a burst from the bezel,
  volume down brings them in to hang, mute brings in the rest and unmute sends them off
  without a burst. Switching between a volume and a brightness bezel jumps the roost to the
  other level without flights.

Not built yet: the glyph is SF `speaker` with Lottie wisps in place of the three waves. The
ghost lives above the bezel.

| | Wisps | Ghost |
|---|---|---|
| Level | Progress = volume (0–3 wisps) | Height follows volume, idle float looping |
| Up | Grow; one wisp breaks off and drifts away | `puff` marker, back to idle |
| Down | Shrink (played backward) | Sinks, `yawn` marker |
| 100% | — | `boo` marker |

### Mute / unmute

- **Mute:** the spider drops on its thread, the web spins over the slashed speaker, and the
  spider stays hanging while the bezel is up. The ghost sinks out of sight.
- **Unmute:** the web tears, the spider climbs back up, and the ghost and wisps come back.

### Everywhere

- All animation models load once at launch and are shared between views and panels.
- Once the fade-out finishes, every scene pauses: nothing runs while the bezel is hidden
  (panels stay ordered in at alpha 0).
- **Reduce Motion:** no swarm or fly-ins; the roost and pumpkin jump to their new state.
- If an animation fails to load, that slot falls back to the standard SF Symbol bezel.
- Lottie's Core Animation engine renders everything. Watch the console for "not supported by
  the Core Animation engine" when adding a file.

## Assets

Animations live in `ReBezel/Seasonal/Halloween/Animations/` as Lottie JSON (it loads
synchronously, which a key press needs).

| # | File | Source | Needs |
|---|---|---|---|
| 1 | `pumpkin.json` | Frames 0–54 of the "Scary Halloween Pumpkin" Lottie, cropped to the pumpkin | **Scrubbable**: every frame works as a still. Friendly at 0, scary at 1. Square, to fill the glyph slot. |
| 2 | `bat-flying.json` | A flying bat cut out of the "Happy Halloween - Animation background" Lottie | Flapping in place, seamless loop |
| 3 | `bat-hanging.json` | LottieFiles or custom | Upside-down idle sway |
| 4 | `wisps.json` | custom | Progress 0→1 = 0→3 wisps, lined up with SF `speaker` at 96 pt light |
| 5 | `ghost.json` | custom or LottieFiles | Markers `idle` (loop), `puff`, `yawn`, `boo` |
| 6 | `spider.json` | [LottieFiles](https://lottiefiles.com/free-animation/spider-LiNoYXFrd9) by Priyanshu Rijhwani | Drop in, dangle |
| 7 | `web.json` | custom | Progress 0→1 spins it in; a `tear` segment |

The graveyard backdrop is `HalloweenGraveyard` in `Assets.xcassets`: a black-on-transparent
template image (1115×177), cropped from the bottom of a larger silhouette with its orange edge
pixels turned into transparency. Each scene tints it with its look's ink
(`HalloweenAssets.graveyard(in:)`).

The spider is under the Lottie Simple License (free for commercial use, no attribution
required). The licences of the background the bat comes from and of the pumpkin are still to
be checked.

### What the downloaded files contain

- **Pumpkin** (1000×1000, 29.97 fps, 54 frames ≈ 1.8 s): the first 54 frames of the "Scary
  Halloween Pumpkin" scene (1600×1200, 140 frames). The jack-o'-lantern's grin widens into a
  jagged, scary one, and flashes red at frames 39–45. Only the `Pumpkin` precomp is kept: the
  scene's backgrounds, ground highlights, skulls, lightning and vines are removed. It sits in a
  precomp shifted so the canvas is a square centred on the pumpkin, with room above it so it
  stands clear of the bats.

- **Bat** (1024×1024, 30 fps, 10 frames ≈ 0.33 s): one of the three identical bats that fly
  across the "Happy Halloween - Animation background" scene (1080×804, 6 s), cut out of it. In
  the scene each bat follows a flight path; the cut-out keeps only the wing flap, which morphs
  the body path between wings raised (frame 0) and wings level (frame 5). The art is drawn
  tilted about 20°, which the scene corrects with the layer's rotation, so the cut-out turns it
  level about the head. The head sits at the canvas centre and the body tip on the carrier's
  feet anchor, and the wingspan is about two thirds of the canvas. The body (group `Body`) is a
  very dark teal and is tinted at runtime. The two orange eyes (`Left Eye`, `Right Eye`) are
  left as they are.
- **Spider** (1024×1024, 30 fps, 180 frames = 6 s): drops in on a rope from above the canvas
  with a bounce (frames 0–37, the rope drawn by a trim path), then swings (rotation until
  frame 146). Mute plays it forward; unmute plays 37→0 to climb back up. The rope starts above
  the canvas, so it can reach from the panel's top edge.

## Phases

Status: phases 0, 1 and 2 are done (October 23).

The update has to be out before October 28 so Sparkle (one check a day) can deliver it by the
start of the window. Ship 1.2.0 on October 26 or 27 at the latest. The custom assets are the
critical path.

0. **Setup.** Add `lottie-spm`; download and check the bat and spider; source the custom assets.
1. **Foundations.** `HUDReading`/`HUDTransition` with tests (new `ReBezelTests` target);
   `AppDelegate` on readings; `SeasonalTheme`, the Preferences switch and the `--season`
   launch argument; the larger panel, `HUDView.glyphOverride`, an empty `HalloweenScene`, and
   pausing on fade-out; a debug menu that fires each transition.
2. **Brightness.** Pumpkin, `BatRoost`, `BatSwarm`.
3. **Volume.** Wisps, `GhostLayer`, marker segments.
4. **Mute / unmute.** `SpiderWebLayer`, web in and tear.
5. **Polish and release.** Every style × position, multiple screens, Reduce Motion; profile with
   Instruments (CPU while hidden, a held-key swarm); release notes and a recorded GIF for the
   README and social posts; `Scripts/release.sh`.
