# Third-person / over-the-shoulder attack camera — history and current state

This tracks what's been tried on the Attack-mode camera (the shot that eases in when you
click an enemy to aim), why each version changed, and where it stands.

Relevant files: `src/logic/camera_orbit_state.gd` (`CameraOrbitState.attack_framing()`, pure
math), `src/view/camera_rig.gd` (`CameraRig.ease_to_attack_framing()`, the tween shell),
`src/logic/unit_geometry.gd` (`UnitGeometry.bounding_sphere()`, the geometry the solver
actually runs on).

## Status: resolved (docs/10 taskblock04 Pass A)

Design 3 (below) replaced offset-tuning with an actual solver, verified against the specific
failure mode Design 2 had (both bodies fit in frame, shooter never behind the camera, no
mid-tween sweep). Live-rendered and checked numerically. Considered done pending any further
play-testing feedback.

## Architecture

- `CameraOrbitState` is a plain `RefCounted` holding `{yaw, pitch, zoom, pan_offset}` plus the
  math to update it. No `SceneTree` dependency — headlessly testable.
- `CameraRig` is the thin `Node3D` shell: a yaw pivot holding a pitch pivot holding the
  `Camera3D` (`local (0,0,zoom)` from the pivot, zero rotation of its own). It only ever reads
  `CameraOrbitState` and writes `Transform3D`/`position` from it.
- Entering Attack mode calls `CameraOrbitState.attack_framing(shooter_sphere, target_sphere)`,
  which returns a target `{yaw, pitch, zoom, pan_offset}`. `CameraRig.ease_to_attack_framing()`
  tweens the *live* state from wherever it currently is to that target over
  `ATTACK_TWEEN_DURATION` (0.4s), via `Tween.tween_method` doing a plain per-field lerp
  (`lerp_angle` for yaw, `lerpf` for pitch/zoom, `Vector3.lerp` for `pan_offset`) each step.
- Orbit/pan/zoom stay live during aim (Design 3 removed the old `CameraRig.locked` flag
  entirely — see below); wheel is still repurposed to step the dartboard layer instead of
  zooming, unrelated and unchanged.

## Design 1 — orbit-pivot-plus-fixed-zoom (taskblock03 Pass C)

The original attack camera reused the *tactical* camera's own orbit-pivot model: keep
orbiting around a pivot, just recenter the pivot and pull to a fixed, closer `ATTACK_ZOOM`
distance, shallower `ATTACK_PITCH`. The pivot could land many units away from either
combatant's actual body — the shooter and target were incidental to where the pivot happened
to end up, not the actual subjects of the shot.

**Symptom:** the target was frequently fully or partially occluded by the shooter's own body,
which — being much closer to the camera than the target — filled a disproportionate amount of
the frame regardless of a modest lateral nudge.

**Tried:** raising `SHOULDER_OFFSET` (0.35 → 0.5 → 0.7 → 1.0) to push the pivot further to one
side. Checked via a screen-space projection diagnostic (shooter vs. target screen separation).
**Did not meaningfully help** — the shooter's own large, close silhouette dominated the frame
regardless of a modest lateral offset; the pivot-based model was never actually anchored to
either body, so nudging it sideways didn't reliably clear the shooter out of the sightline.
Abandoned rather than pushed further, since the model itself was the problem, not the tuning.

## Design 2 — position-at-shooter, look-at-target

Per an explicit request ("tie the third person camera to the torso of the AIMING unit, offset
right and up... point the camera at the torso of the TARGETED unit"), replaced the orbit-pivot
model outright:

- `camera_pos = shooter_torso + ATTACK_UP_OFFSET (up) + ATTACK_RIGHT_OFFSET (perpendicular to
  the shooter→target line)`
- Orientation: a direct look-at solve — `pitch = asin(look_dir.y)`; `yaw = atan2(-horiz.x,
  -horiz.y)`.
- `zoom = 0` so `pan_offset` (the pivot) *is* the camera's exact world position — no leftover
  orbit-distance term.

**Verified, not hand-derived:** a headless diagnostic (`diag_lookat.gd`, scratchpad — not
checked in) built a real `CameraRig`, applied computed `{yaw, pitch, pan_offset}`, and read the
actual `Camera3D.global_transform` back out, across several non-coplanar shooter/target pairs.

**Bug caught in the process:** the first yaw formula (`Vector2(0,1).angle_to(horiz)`) only
agreed with the verified-correct `atan2(-horiz.x, -horiz.y)` when the shooter and target
shared a row or column. Fixed; a diagonal case stayed in the test suite.

Constants at the time: `ATTACK_RIGHT_OFFSET = 0.9`, `ATTACK_UP_OFFSET = 0.6`,
`ATTACK_TORSO_HEIGHT = 1.25` (hardcoded humanoid chest height — see A2 below for why this had
to go).

### Investigation — "still very strange"

Stepped a live scene through the actual tween (before / tween-start / tween-mid / fully-eased)
and screenshotted each stage.

**Finding 1 — the final shot showed the *target*, not the shooter, and no "shoulder" was
visible at all.** At rest, `camera_pos` was only ~1.08 units from the shooter's own torso box —
smaller than the shooter's own body. Hiding the shooter's `UnitView` and re-rendering proved
the close-up figure on screen the whole time was the target, correctly centered (look-at math
was fine) with the reticle on its chest — but the shooter, the thing the shot is meant to be
framed *over the shoulder of*, was never in frame.

**Finding 2 — the tween itself passes close enough to the shooter's body to glitch.**
`ease_to_attack_framing` interpolates `pan_offset` *linearly* from the current (distant,
tactical) camera position to the tight final position; the straight-line path swept close
enough to the shooter's geometry partway through to visibly balloon it across half the screen
mid-transition.

**First fix tried:** pulled `ATTACK_RIGHT_OFFSET`/`ATTACK_UP_OFFSET` back roughly 2.5x (0.9→2.5,
0.6→1.5). Measurably better (mid-tween silhouette dropped from ~27% to ~11% of frame width),
still reported as "funky." Root cause turned out to be structural, not a tuning problem — see
Design 3.

## Design 3 — solved framing, orbit around the target (docs/10 taskblock04 Pass A)

**Why the pull-back could never actually work:** both `ATTACK_RIGHT_OFFSET` and
`ATTACK_UP_OFFSET` are perpendicular to the shooter→target view axis. Growing them slides the
camera sideways *past* the shooter — they can never pull it *into* the frustum along the one
axis that matters. Measured against the usable half-FOV (≈31.9°, see below):

| Config | Shooter's angle off frame centre | Visible? |
|---|---|---|
| Design 2 original (R=0.9, U=0.6) | 79.8° | no |
| After the pull-back (R=2.5, U=1.5) | 64.1° | no |

The pull-back bought 15° in an axis that can't reach. There was no "back" offset — nothing put
the shooter *between* the camera and the target, which is what "over the shoulder" means.

### The fix: a solver, not an offset

`attack_framing(shooter, target)` now takes each unit's own **bounding sphere**
(`UnitGeometry.bounding_sphere()`, built from `UnitGeometry.placements()` — every living box's
actual world-space corners, never a hardcoded body size, so a giant enemy solves its own
correct distance with no special-casing):

```
1. bounds: {center, radius} for both units, from their real geometry.
2. direction: to_target = normalize(target.center - shooter.center)   [horizontal]
              right     = perpendicular to to_target
   camera_pos = shooter.center - to_target*BACK + right*RIGHT + up*UP
3. solve: binary search the smallest BACK such that both spheres' angular
          footprint (angle to centre + asin(radius/distance)) fits inside
          usable_half_fov = deg_to_rad(75/2) * 0.85  (Camera3D's default
          vertical FOV, margin 0.85).
4. express the result as an orbit around the TARGET: pan_offset =
   target.center, zoom = |camera_pos - target.center|, {yaw, pitch}
   derived from the offset direction.
```

`-to_target*BACK` is the missing axis Design 1/2 never had — it pulls the camera backward
along the shot line, putting the shooter *between* the camera and the target.

**Orbiting the target, not sitting at a literal point, is what actually kills the tween
glitch.** Design 2's `zoom = 0` was a look-at camera shoehorned into an orbit parameterisation;
lerping `{yaw, pitch, zoom, pan_offset}` between "far orbit round a pivot" and "camera at a
literal point glued to the shooter" had no reason to produce a sane path. Making the pivot the
*target's own bounding sphere center* means the tween is now pivot-lerp + zoom-lerp +
yaw/pitch-lerp — an arc around a moving pivot, at sane distance throughout, that never goes
near the shooter's body. Verified with a mid-tween clearance test
(`test_mid_tween_the_camera_never_gets_close_to_the_shooter`, `test_camera_rig.gd`) stepping
the tween to 10/25/50/75/90% and checking clearance from the shooter's sphere at each point —
passes with real margin at every step, no special-casing required.

As a consequence, orbiting live during aim is now safe (the pivot is stable and meaningful),
so `CameraRig.locked` — which only ever existed because the old reticle screen-to-shot-plane
mapping assumed a fixed camera angle (separately fixed by `AimPlaneGeometry`'s raycast
approach) — was removed outright as dead weight, not just left unused.

**Yaw/pitch formula:** unchanged from Design 2 (`asin`/`atan2`, already verified against a real
Camera3D). For this rig's topology (camera at local `+Z*zoom` from a pivot, zero rotation of
its own), the camera always faces its pivot by construction — the same `{yaw, pitch}` pair that
made a `zoom=0` camera look *at* the target now places a `zoom=|offset|` orbit camera at the
right point *around* the target pivot. Only what `zoom`/`pan_offset` represent changed.

### Verification

- `test_camera_orbit_state.gd`: both spheres fit across adjacent/mid/far/diagonal pairs; the
  shooter is provably in front of the camera (`dot(shooter - cam, look) > 0`); a giant target
  forces a larger BACK than a standard one; the solved BACK is the *smallest* qualifying one
  (nudging the camera closer breaks the fit); deterministic; the pivot really is the target's
  sphere, not a literal point.
- `test_camera_rig.gd`: the target's screen-projected centre lands at the exact viewport
  centre (the orbit-pivot property, checked against a live `Camera3D`); mid-tween clearance
  from the shooter's sphere holds throughout the transition.
- Live-rendered (seed 2, shooter cell (3,1), target cell (9,5)): both units visible in the same
  frame at rest, and no ballooning glitch at any sampled mid-tween fraction — screenshots
  compared directly against the Design 2 pull-back's equivalent renders.

Current constants: `ATTACK_RIGHT_OFFSET = 0.9`, `ATTACK_UP_OFFSET = 0.6` (back to their
original, small values — they're a lateral/vertical nudge now, not what fits anything;
`CAMERA_FOV_DEG = 75.0` (must track the real `Camera3D`'s default — never set explicitly
elsewhere), `ATTACK_MARGIN = 0.85`, `ATTACK_BACK_MAX = 200.0`,
`ATTACK_BACK_ITERATIONS = 40`, `ATTACK_PITCH = -0.25` (degenerate-case fallback only),
`ATTACK_TWEEN_DURATION = 0.4`.

## Open questions / untried directions

- **Show the shooter on purpose, not just avoid hiding it.** The solver guarantees both bodies
  *fit*; it doesn't compose them (rule of thirds, shooter kept specifically in the near
  foreground, etc.). Whether that's worth doing depends on what "over the shoulder" is supposed
  to communicate beyond "both combatants are visible."
- **Elevation.** Everything above assumes a flat single-elevation grid. Bounding spheres
  already generalize correctly to any geometry, but the RIGHT/UP offset axes and the
  degenerate same-point fallback haven't been thought through for a shot across a height
  difference, once that exists.
- **Field of view.** Untouched — `Camera3D` uses its engine default throughout. A narrower FOV
  at close range was a candidate before the solver existed; may be moot now that BACK is solved
  rather than fixed, but not re-examined.
