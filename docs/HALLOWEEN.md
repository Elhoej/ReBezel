# Halloween seasonal bezel

A themed bezel for the days around Halloween, used as a marketing moment. The bezel itself
stays the canvas: same size, styles and positions. Lottie animations play in and around it,
driven by the six things a key can do: volume up, volume down, mute, unmute, brightness up and
brightness down.

## Decisions

- **Season window:** October 28 to November 3 (three days either side of the 31st), in the
  user's own calendar. On by default; Preferences has a switch that turns seasonal bezels off
  completely.
- **Volume at 0 counts as mute.** The bezel already treats "muted" and "turned all the way down"
  the same (slashed speaker, empty bar), and the spider follows that.
- **The muted glyph stays `speaker.slash`**, with the web drawn over it.
- **Nothing extra happens at the ends.** Brightness up at 100% or volume down at 0% changes no
  level, so no animation plays.
- **The ghost says "BOO!" at 100% volume.**

## How triggers are found

Callers don't say what happened; they say what the level is now, as an `HUDReading`
(`.volume(level:muted:)`, `.brightness(level:)` or `.caption(symbol:text:)`). The HUD compares
each reading with the previous one of its kind and derives an `HUDTransition`.

This matters because the Touch Bar observer echoes ReBezel's own key changes back as a second
reading of the same level. Derived from the difference, that echo is "no change" and nothing
fires twice. Keys, the Touch Bar and the Preferences preview all go through the same path.

- Brightness is compared per display (Control+brightness changes an external one).
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
                               └─ pauses the scene once faded out           ├─ BatRoost         (below the bezel)
                                                                            ├─ BatSwarm         (in front, whole panel)
                                                                            └─ SpiderWebLayer   (in front, over the glyph)
```

While a season is active the panel's transparent margin grows from 40 to 240 points
(680×680), giving the bats room to fly out. Out of season the panel is exactly as before.

Back to front:

1. **Ghost**, in a clip view whose bottom edge is the bezel's top edge, so it rises from behind
   the bezel and never sits under (and gets lensed by) the glass.
2. **Bezel.** `HUDView.glyphOverride` replaces the SF Symbol with the scene's own view.
3. **Roost**: up to 10 bats hanging from the bezel's bottom edge, at staggered heights.
4. **Swarm**: free-flying bats over the whole panel, faded out before the panel edge.
5. **Spider and web**, over the glyph.

### Brightness

- **Jack-o'-lantern** replaces the sun. Animation progress = brightness. Each change plays from
  the progress on screen to the new level, so up runs it forward and down runs it backward,
  and a key repeat continues from wherever the previous step was.
- **Roost:** `ceil((1 − brightness) × 10)` bats. When the bezel appears they are already in
  place; only changes animate. With 16 steps and 10 bats some presses don't change the count;
  the pumpkin still moves on every press.
- **Up:** the bats leaving the roost take off, joined by 3–5 more from behind the bezel, flying
  outward in random directions. At most 24 bats are in the air at once.
- **Down:** bats fly in from random points at the panel edge to the next free roost spots and
  switch to the hanging animation.

Bats are pooled `LottieAnimationLayer`s playing one flapping loop, each moved along its own
random curved path by Core Animation with a random speed, size, start frame and left/right
flip. A Lottie file can't spawn or steer copies of itself.

### Volume

The glyph is SF `speaker` with Lottie wisps in place of the three waves. The ghost lives above
the bezel.

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
| 1 | `pumpkin.json` | custom or LottieFiles | **Scrubbable**: every frame works as a still. At 0 only faint eyes glow. |
| 2 | `bat-flying.json` | [LottieFiles](https://lottiefiles.com/free-animation/bat-halloween-XkSYPjzHs7) | Flapping in place, seamless loop |
| 3 | `bat-hanging.json` | LottieFiles or custom | Upside-down idle sway |
| 4 | `wisps.json` | custom | Progress 0→1 = 0→3 wisps, lined up with SF `speaker` at 96 pt light |
| 5 | `ghost.json` | custom or LottieFiles | Markers `idle` (loop), `puff`, `yawn`, `boo` |
| 6 | `spider.json` | [LottieFiles](https://lottiefiles.com/free-animation/spider-LiNoYXFrd9) by Priyanshu Rijhwani | Drop in, dangle |
| 7 | `web.json` | custom | Progress 0→1 spins it in; a `tear` segment |

Both LottieFiles animations are under the Lottie Simple License (free for commercial use, no
attribution required).

### What the two downloaded files contain

- **Bat** (1024×1024, 60 fps, 49 frames ≈ 0.8 s): one black bat. The wings flap by morphing a
  single path, and the whole bat bobs 20 units up and down. It **flaps in place**, so it works
  as the swarm sprite. Two things to fix or work around: the bat sits off-center in its canvas
  (it needs re-framing, or an offset when placed), and the path's last keyframe differs from its
  first, so check the loop seam by eye. It is solid black, which disappears on dark
  wallpapers; tint it at runtime with a color value provider.
- **Spider** (1024×1024, 30 fps, 180 frames = 6 s): drops in on a rope from above the canvas
  with a bounce (frames 0–37, the rope drawn by a trim path), then swings (rotation until
  frame 146). Mute plays it forward; unmute plays 37→0 to climb back up. The rope starts above
  the canvas, so it can reach from the panel's top edge.

## Phases

Status: phases 0 and 1 are done (October 23).

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
