# Checkpoint 8

Generated 2026-07-25T08:16:31Z, by launching the real project (`godot --path .`, a real GPU frame via `--display-driver x11`) and driving `BattleScene`/`TacticsController`/`CameraRig` exactly as a player would, then reading back the rendered frame — not a mockup.

taskblock-40 Pass D: "hand the supervisor a loadable scenario, not a description." Three
hand-built scenarios — a real placed-Surface grid (`GridFixture`, the same call
`MapGen._emit` makes), loaded through the real `BattleScene.load_battle()` entry point,
camera framed through the real `CameraRig.ease_to_framing()` "entering aim" call (tb34 Pass D) —
never a mock, never a re-derived formula. Same grid shape in all three: a ground floor, a real
3x3 elevated platform (3 levels up) at the far side, one real destructible wall on the ground
floor directly between the two areas.

- **`a_target_above.png`** — shooter on the ground, target on the elevated platform. Renders as a
  real over-the-shoulder shot, steep but coherent — this is the one to judge Pass B's tilt-angle
  question against.
- **`b_target_below.png`** — the mirror: shooter on the elevated platform, target on the ground.
  **This one is not a clean framing sample — see BR40.01 below; it currently demonstrates a real
  solver limitation, not a judgment call.**
- **`c_same_level_control.png`** — both on the ground floor, same wall, nothing elevated — the
  baseline every other shot is judged against. Both units clearly visible, wall clearly visible,
  no cutout needed at this angle (target isn't behind the wall from the camera's own solved
  position) and none is visibly present.

Regenerate with `./checkpoint.sh 8` — see `tools/checkpoints/checkpoint_8.gd` for the driver
script and `run.log` for its stdout (checked for script errors on launch).

## BR40.01 — found building this checkpoint, not a judgment call

`b_target_below.png` doesn't show a target-below shot at all — it shows a wall of green filling
almost the whole frame, no target, no wall visible. Root-caused, not just observed: the solved
camera position (`(8.49, 3.6, 2.1)`) sits **past the far edge of the platform the shooter is
standing on** (which only spans x in [4,6]) — `_solve_back` pushes the camera backward far enough
to fit both bodies' angular footprint, with no awareness that "backward" here walks it off the
platform's own edge. What's on screen is the platform's own solid mass, now between the camera and
everything else. Full root-cause and candidate fixes are on `docs/BUGS.md` **BR40.01** (owner
`CC`) — nothing to re-derive here, just confirm it still reproduces if you regenerate this
checkpoint after any camera-rig change.

## Checklist

One line per item, answerable yes/no without interpretation. Numbers are taskblock-40 Pass B's
own measured height-delta matrix (`test_camera_orbit_state.gd`'s
`test_pass_b_height_delta_matrix_always_fits_and_never_drops_below_the_lower_body`, run against
the exact same solver this checkpoint's camera uses) — every hard invariant they check already
passed headlessly; these questions are for the one thing a number can't answer.

**Camera framing (tb40 Pass B — numerically clean; these ask whether it also LOOKS right):**
1. In `a_target_above.png`, are both the shooter and the target fully on screen?
2. In `c_same_level_control.png`, are both units fully on screen, framed the same familiar way
   as any flat-map shot?
3. Is the shooter positioned between the camera and the target in `a_target_above.png` (a real
   over-the-shoulder shot, not the shooter's own back to the camera or off to one side)?
4. Pass B's own measured vertical look angle grows from ~7° at the same level to ~25-34° at a
   6-level height delta (bounded by the fit search itself, never runaway) — comparing
   `a_target_above.png` against `c_same_level_control.png`: does that tilt still read as a
   coherent aim shot, or does it look broken/disorienting?
5. Does BR40.01's failure mode (camera walking off a small elevated stand) look like something
   that would come up often on real generated maps, or only on a deliberately narrow platform like
   this fixture's 3x3? Worth a priority call, not just a confirmation.

**Wall cutout under elevation (tb40 Pass C, BR32.05 — reasoned from shader source only, never
rendered before now; confirm, don't hunt):**
6. In `c_same_level_control.png`, is the wall rendered solid (no cutout), matching the fact that
   nothing is actually between the camera and either unit at this angle?
7. In `a_target_above.png`, can you find the wall at all, or does it read as fully hidden behind
   the shooter's own body from this angle (plausible — wall and shooter are only 1-2 cells apart,
   nearly on the same sightline)? If hidden, that's not evidence either way for BR32.05 — note it
   and, if a clean look at the cutout matters, reposition the wall via `Inject...` (BoutInjector)
   in a live session rather than reading a null result out of this fixed angle.
8. In any screenshot, is a chunk cut from a part of the wall that is clearly NOT between the
   camera and either unit (BR32.05's own named symptom)?
9. In any screenshot, does a cutout expose unlit/placeholder wall-interior texture where it
   shouldn't (BR32.05's own "interior-texture exposure" sub-symptom)?

If 8 or 9 come back yes, that's live confirmation of BR32.05's own elevation finding (tb40 Pass
C) — note which screenshot and roughly where on the wall; no new `docs/BUGS.md` entry needed,
append to BR32.05 instead (already covers this root cause).

Headless coverage for everything these screenshots can't show — both-fit and never-below-body
across the full +/-1, +/-3, +/-6 delta matrix, continuity across the zero crossing, the pinned
same-level regression guard — lives in `test/unit/logic/test_camera_orbit_state.gd`.
