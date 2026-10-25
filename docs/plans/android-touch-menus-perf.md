# Plan: Android touch controls, menus that fit, 120 Hz on the Odin 3

Kevin's ask (2026-10-24): touch controls, then menu sizing on Android (the menus no longer
fit), then Odin 3 performance: 120 fps, dips no lower than ~105, never below 100.

A session that picks this up: read this file and `git log --oneline -5` on the branch in
progress, then continue from the first unticked item. Device recipes (adb, release APK,
`--perf` on the device): the Android notes in `docs/open-items.md` and the memory
`android-build`.

| # | PR | Branch | Base | Status |
|---|---|---|---|---|
| 1 | Menus fit on any screen (diagnose on the Odin, fix, a test across screen sizes) | `android-menu-fit` | `main` | not started |
| 2 | Touch fight controls (`TouchPad` + overlay) | `touch-controls` | `main` | not started |
| 3 | Touch-friendly menus (big rows, drag to scroll, tap targets) | `touch-menus` | PR 1 | not started |
| 4 | Odin 3 perf: measure at 120, breakdown per part | `odin-perf-measure` | `main` | not started |
| 5 | Odin 3 perf: the fixes the measurement points at (maybe 2–3 PRs) | `odin-perf-*` | PR 4 | not started |
| 6 | 120 by default on devices that hold it | `odin-120-default` | PR 5 | not started |

Menus come first even though touch was asked first: they're broken now, and touch menus (PR 3)
build on the fix. PR 2 (fight controls) and PR 4 (measuring) don't depend on it and can run
in parallel. None of this touches `src/sim/`: touch input is the same input bits a pad
sends, so there's **no NET_VERSION bump** and touch players can play PC players online.

---

## 1. Menus fit on any screen

### What we know
- The canvas is 960 x 540 grid pixels (480 x 270 canvas units, `window/stretch/scale=2`),
  aspect `expand`. `main.gd:_apply_pixel_scale` snaps the window to whole screen pixels per
  canvas unit (4 at 1920 x 1080), and runs again on `size_changed`.
- `_fit_window` skips mobile; the Odin's panel is 1080 x 1920 (1920 x 1080 landscape, 16:9).
- Since the last good Android check (PR #111, Oct 21) the menus changed a lot: two-pane
  menus (#126), menu cards (#128), the pixel font everywhere (`bf5d1fb`, wider text), the
  title and results screens (`e95cdf7`). All of it was checked on desktop 16:9 only.

### Suspects (in order)
1. **The window Android reports isn't 1920 x 1080** (status or nav bar, the cutout, or the
   size read in portrait before the rotation), so the snap lands somewhere unexpected.
2. **The layouts overflow 480 x 270** at the pixel font's widths in some pages, and desktop
   hides it because desktop windows are usually bigger than the screen area they test.
3. Phones that aren't 16:9 (20:9 at 2400 x 1080, 4:3 tablets) were never checked.

### Steps
- [ ] With the Odin plugged in: `adb exec-out screencap -p` of every menu page; log
  `get_window().size`, `content_scale_factor`, `get_visible_rect()`,
  `DisplayServer.get_display_safe_area()` at startup and on each `size_changed`.
- [ ] Ask Kevin what "doesn't fit" looks like (cut off at an edge? overlapping? too small
  to read?) and match it to the screenshots.
- [ ] Reproduce on PC at the reported size (`--resolution=WxH`) so the fix can be
  checked without the device.
- [ ] Fix the cause (snap or layout). Keep menus and HUD inside the **safe area**
  (cutouts, rounded corners).
- [ ] `tests/test_ui_fit.gd`: build every menu page (the same journey as
  `test_journey`) at 1920 x 1080, 2400 x 1080 (20:9), 2340 x 1080, 1280 x 800 (16:10),
  2048 x 1536 (4:3) and 1440 x 810; fail when a visible control's rect leaves the visible
  rect or two rows overlap. Headless skips `_apply_pixel_scale`, so the test sets the
  window's content scale itself through `pixel_scale_factor`.

## 2. Touch fight controls

### Shape
- **`src/input/touch_pad.gd` (TouchPad)**: pure logic like `MouseOrders`. It's fed
  `InputEventScreenTouch` / `InputEventScreenDrag` (multi-touch by `index`) and returns
  the input bits for a tick. Tests drive it with synthetic events.
- **`PlayerInput`**: a third device, `Device.TOUCH`. `bits()` ORs the touch pad's
  bits in, so aim assist and online work unchanged; `label`/`help_text` get touch
  wording.
- **`src/view/touch_overlay.gd`**: draws the stick and buttons from the TouchPad's state,
  plus each move's cooldown and Surge meter on its button (read from the sim, never
  written). It doesn't draw itself on a frame where nothing changed, so it costs nothing at
  120 Hz.

### Layout (landscape, both thumbs)
- **Left: a floating move stick.** It appears where the left thumb lands in the left ~40%
  of the screen, has 64 steps through `SimDefs` move bits (`IN_MOVE`), and returns to its
  rest spot when released.
- **Right: an arc of buttons.** Light (the biggest, nearest the thumb), Heavy, Skill 1,
  Skill 2, Surge (lit when the meter is full), Dodge, Guard (hold). Tag shows only in
  Duel. Pause is a small button in the top corner (Back already pauses).
- **Aiming:**
  - **Tap** a button and it fires the way you're moving, or the way you face, with aim
    assist. Touch uses the wider `ASSIST_DEG` (25°), not the stick's 12°.
  - **Drag** off Heavy, Skill 1, Skill 2 or Surge and it aims instead. It draws the move's
    reach as a true circle and line (the floor-circle rule), and fires on release with
    exact aim (`IN_AIM`). Drag back onto the button to cancel.
  - Light is tap-only, because release-to-fire would slow combos.
  - The 10-tick input buffer keeps tapped combos working as they do now.
- **Dodge** goes the way the stick points (the stick's last way if released), like the pad.
- **Show and hide:** the overlay shows on the first touch in a fight, and hides on any
  pad or keyboard input. On the Odin it starts hidden, because a pad is attached.

### Settings (Controls > Touch)
- [ ] Opacity, button size (3 steps), left-handed (mirror), aim style (tap + drag / tap
  only).
- [ ] Later, if Kevin wants it: drag the buttons into your own layout (saved per device).

### Steps
- [ ] TouchPad + Device.TOUCH + `tests/test_touch.gd`:
  - each button's bits;
  - the stick's 64 steps match `move_from_bits`;
  - drag-aim fires on release with `IN_AIM`, and dragging back cancels;
  - two fingers at once (stick + button);
  - a lost touch (app paused) releases everything.
- [ ] The overlay, with a screenshot pass at 1920 x 1080 and 2400 x 1080 (the
  `--shots` recipe, a `--touch-demo` flag that plays a recorded touch script like the
  showcases).
- [ ] Move HUD pieces that sit under the thumbs (bottom corners) when touch is on.
- [ ] On the Odin: play a 1v1 and a 4v4 by touch; Kevin judges the feel.
- [ ] MECHANICS.md: the new CLI flag; `src/input/CLAUDE.md`: TouchPad gotchas; the codebase
  map rows for "touch".

## 3. Touch-friendly menus

At the scale of 4 screen pixels per canvas unit, a menu row (text size 9) is about 4 mm
tall on the Odin's 6" screen. A finger needs ~9 mm, about 30 canvas units.

- [ ] Taps already arrive as mouse clicks (`emulate_mouse_from_touch` defaults on). Check
  the "mouse focuses what it's over" rule doesn't make a tap jump focus twice.
- [ ] **Touch layout for `UiScreen`** (on when the last input was touch):
  - rows twice as tall, in one column;
  - the side panel becomes a line under the focused row (or a tap-and-hold), and cards
    are hidden;
  - long lists scroll by drag.
- [ ] Option rows (`< value >`): the arrows become tappable buttons.
- [ ] Character select: tap a portrait to pick for player 1, and a Ready button.
- [ ] A Back button on screen in the corner (the Android Back key still works).
- [ ] `test_ui_fit.gd` also runs the touch layout; `test_ui` drives a page by synthetic taps.

## 4–6. 120 Hz on the Odin 3

### The budget, and what "105 fps" means
At 120 Hz with vsync, every frame has 8.33 ms. A frame that misses shows for two
refreshes (16.7 ms), which you see as a hitch. So **an fps counter at 105 means about 15
hitches a second**, which looks stuttery even though the number looks high. I'd set the
goal on missed frames, not on the fps number:

- **Target:** 4v4 CTF at Rage (the worst case, `--mode=53 --level=3 --seed=7`) on a
  release APK: under 1 missed frame a second on average, and no 1-second window below
  110 fps.
- **Floor:** no 1-second window below 100 fps (Kevin's line), in a 10-minute run so the
  CPU is heat-soaked (thermal throttling shows up after a few minutes).
- 1v1 and 2v2: no misses at all.

### What we know (Oct 21, release APK)
- At 60 Hz: game 3.6 ms average / 6.5 p99, sim 1.06 ms, no dropped frames.
- At 120 Hz: tick frames p99 15.8 ms, 48% of frames over 8.3 ms (nearly every frame that
  carries a tick), ~2 stutters a second.
- GDScript runs 1.6–2x slower on the Odin than on Kevin's PC.
- The game's own work (3.6 ms) doesn't fill 8.3 ms by itself, so **rendering (render CPU
  or the GPU) is probably half the cost.** It hasn't been measured on the device yet.
- **Ruled out:** render interpolation (Kevin: never); a separate render thread (crashes
  with gl_compatibility in 4.7.2).

### PR 4: measure
- [ ] `--perf` on the Odin at a 120 cap, 4v4 CTF and 1v1, with the breakdown per part (input,
  CPUs, sim, each view, HUD, render CPU, render GPU), for **tick frames and off frames**
  separately.
- [ ] Draw calls and canvas items per frame (`RenderingServer.get_rendering_info`) on the
  same runs.
- [ ] A 10-minute heat-soak run; log the frame times per minute. Pin the Odin's
  performance mode (Balanced vs Performance) and say which one each number used.
- [ ] Write the numbers into this file. They decide PR 5.

### PR 5: likely levers (ordered once PR 4's numbers are in)
1. **Spread the tick frame over the off frame.** At 120 Hz each tick has one frame with
   no tick in it, and that frame sits nearly empty. Move work that doesn't change what's
   on screen this frame there: HUD text rebuilds, floor band repaints (`_pending`),
   crowd, minimap, weather lightmap updates, CPU thinking for the next tick (it already
   runs on worker threads; start it on the off frame). Positions still snap on the tick
   frame, so this isn't interpolation.
2. **Rendering cost, if PR 4 says it's the big half:**
   - full-screen layers drawn over each other (weather, fore view, grade or vignette,
     lightmap);
   - canvas items that break batching;
   - redraws when nothing changed.
   Mobile quality settings already exist (glow off); add to them, e.g. fewer particles
   or a cheaper crowd and weather on mobile, each listed in Settings > Video.
3. **GDScript hot spots** that cost twice as much on ARM: the per-tick view refresh,
   `_steer` probes, FxView. Use the same probes as the PC passes.
4. **Try the Mobile (Vulkan) renderer on Android as an experiment.** It may submit draws
   more cheaply, and Godot's Android frame pacing works with Vulkan. Risk: shaders and
   the look may differ from gl_compatibility, so check screenshots side by side. Keep it
   only if it's clearly faster and looks the same.
5. **Not proposed:** stepping the sim early on the off frame. It would add 8 ms of input
   lag, a cost Kevin should rule on rather than one the plan quietly takes.

### PR 6: the default
- [ ] `Main.default_fps` is 120 on a device that passed the benchmark (the Odin, by model),
  60 elsewhere. Or ask on first launch, after a 10-second check run? Kevin to choose.
- [ ] Android's own refresh setting still pins apps to 60 unless set to 120. The game
  can't override it, so show a hint in Settings > Video when the screen reports 60.

---

## Open questions for Kevin
1. What does "the menus don't fit" look like on the Odin: cut off, overlapping, or too small?
2. Touch aiming: tap to auto-aim plus drag to aim on the big moves (recommended), or tap only?
3. The perf target: OK to judge it by missed frames (under 1 a second) instead of the fps
   number? 105 fps on the counter is about 15 visible hitches a second.
4. 120 by default only on devices that pass a check, or on all Android with 60 as the fallback?
5. The Vulkan renderer experiment on Android: worth trying if the GPU turns out to be the
   bottleneck?

---

## Progress (2026-10-24, paused)

Kevin's answers: (1) menus are **cut off at the edges** on some pages; (2) touch aiming is
Claude's choice (tap + drag-aim on the big moves, as planned); (3) judge perf by **both**
the fps number and missed frames, and report **1% and 0.1% lows** of frame times; (4) **60
stays the Android default**, but 120 must hold on the Odin 3 (selectable in Settings);
(5) **try the Vulkan (Mobile) renderer** and decide if it's viable. Kevin has the Odin
for testing tonight.

Menu fit, reproduced on PC (fresh `APPDATA`, `--resolution 1920x1080 -- --menu=<page>
--shots=40`): any 1080-tall window (1920 x 1080 = the Odin, 2400 x 1080) cuts off
- **Settings > Video**: the Camera rows from #194 push the page past 270 canvas units;
  Back is off-screen and the key hints overlap the last rows. Kevin's 3440 x 1440 hides it
  (288 units tall there). Also broken on any 1080p PC.
- **Single player > Team battles**: the panel's mode facts run past its right edge.
Fine at 1080: main, single, settings, controls, game, audio, look, the three remap pages,
brawl, practice. Not checked yet: character select, pause, online pages, results, ready
check (do them on the Odin).

Vulkan: started a PC run comparing gl_compatibility vs `--rendering-method mobile` vs mobile
+ `--render-thread separate` (4v4 CTF, `--perf`, shots at 300/1200); stopped before it
finished. Re-run it. Why it's promising: the only shaders are two plain canvas_item ones
(`grade.gdshader`, `flash.gdshader`), no environment or 3D, so the look should match; and
the separate render thread that crashed was a gl_compatibility crash, so it may work on
Vulkan and move render CPU off the main thread. Note: fresh-APPDATA runs print harmless
`shader_gles3.cpp:802` errors.

## Progress (2026-10-24, resumed)

- **PR 1 (`android-menu-fit`)**: pages short of room drop the "CREATURE ARENA" name over a
  sub-page's title, then scroll their column (`UiScreen._fit_rows`, follows focus, thin bar);
  card facts are one line (narrower spaces when needed; 18 reworded to fit); the Single
  player pages' panel is 170 wide (rows 226). `tests/test_ui_fit.gd` opens every menu page,
  the character select, pause, training pause/options/fighters, results, the four online
  pages and the ready check at 1920x1080, 1440x810, 2400x1080, 2340x1080, 1280x800 and
  2048x1536, and checks every row's facts for every choice. It found more than the two known
  pages: Challenges ran off the bottom at 1080, and most rows' facts were silently clipped.
  Still to do on the Odin: screenshots of the same pages (the safe area wasn't checked).
- **PR 2 (`touch-controls`)**: in progress in a separate worktree.
