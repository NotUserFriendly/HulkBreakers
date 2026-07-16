# Third-person / over-the-shoulder attack camera — history and current state

This tracks what's been tried on the Attack-mode camera (the shot that eases in when you
click an enemy to aim), why each version changed, and where it stands. The camera has gone
through three real designs and is still not considered "right" — this file exists so the next
pass doesn't re-discover the same dead ends.

Relevant files: `src/logic/camera_orbit_state.gd` (`CameraOrbitState.attack_framing()`, pure
math), `src/view/camera_rig.gd` (`CameraRig.ease_to_attack_framing()`, the tween shell).

## Architecture

- `CameraOrbitState` is a plain `RefCounted` holding `{yaw, pitch, zoom, pan_offset}` plus the
  math to update it. No `SceneTree` dependency — headlessly testable.
- `CameraRig` is the thin `Node3D` shell: a yaw pivot holding a pitch pivot holding the
  `Camera3D` (`local (0,0,zoom)` from the pivot, zero rotation of its own). It only ever reads
  `CameraOrbitState` and writes `Transform3D`/`position` from it.
- Entering Attack mode calls `CameraOrbitState.attack_framing(shooter_pos, target_pos)`, which
  returns a target `{yaw, pitch, zoom, pan_offset}`. `CameraRig.ease_to_attack_framing()`
  tweens the *live* state from wherever it currently is to that target over
  `ATTACK_TWEEN_DURATION` (0.4s), via `Tween.tween_method` doing a plain per-field lerp
  (`lerp_angle` for yaw, `lerpf` for pitch/zoom, `Vector3.lerp` for `pan_offset`) each step.
- While aiming, `CameraRig.locked = true` blocks all live orbit/pan/zoom input outright.

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
- Orientation: a direct look-at solve — `pitch = asin(look_dir.y)` (pitch is the *second*
  Euler rotation, always applied around the already-yawed frame's own local X, so it depends
  only on the look direction's Y component regardless of yaw); `yaw = atan2(-horiz.x,
  -horiz.y)` where `horiz` is the look direction's horizontal (X, Z) component.
- `zoom = 0` so `pan_offset` (the pivot) *is* the camera's exact world position — no leftover
  orbit-distance term.

**Verified, not hand-derived:** wrote a headless diagnostic (`diag_lookat.gd`, scratchpad —
not checked in) that builds a real `CameraRig`, applies computed `{yaw, pitch, pan_offset}`,
and reads the actual `Camera3D.global_transform` back out, across several non-coplanar
shooter/target pairs, confirming the formulas actually produce a camera that looks at the
target — not just formulas that look plausible on paper.

**Bug caught in the process:** the first yaw formula (`Vector2(0,1).angle_to(horiz)`) only
agreed with the verified-correct `atan2(-horiz.x, -horiz.y)` when the shooter and target
shared a row or column — which was every case the original hand-written tests happened to
cover. A diagonal (non-coplanar) test case exposed it. Fixed, and a diagonal case is now
permanently in the test suite (`test_camera_orbit_state.gd`,
`test_attack_framing_actually_looks_at_the_targets_torso`) so this can't quietly regress.

Initial constants: `ATTACK_RIGHT_OFFSET = 0.9`, `ATTACK_UP_OFFSET = 0.6`,
`ATTACK_TORSO_HEIGHT = 1.25` (matches `ResolutionPlayer.TRACER_MUZZLE_HEIGHT`).

## Investigation — "still very strange" (this pass)

Reported after Design 2 had been live for a while. Investigated by stepping a live scene
through the actual tween via scratchpad diagnostics (not checked in) and screenshotting at
each stage: before aiming, tween start, tween mid-point (`Tween.custom_step()` to a known
fraction), and fully eased.

**Finding 1 — the final shot was showing the *target*, not the shooter, and no "shoulder" was
visible at all.** At rest, `camera_pos` was only ~1.08 units from the shooter's own torso
(box size `(0.5, 0.7, 0.28)`) — smaller than the shooter's own body. To confirm which unit was
actually on screen, the shooter's `UnitView` was hidden (`view.visible = false`) and the scene
re-rendered: the close-up humanoid figure **did not disappear**. It was the target the whole
time, correctly centered (its screen-projected position landed exactly at the viewport
center, confirming the look-at math itself is correct) with the aim reticle on its chest. The
shooter — the thing the shot is supposed to be framed *over the shoulder of* — was never in
frame. This reads less like an over-the-shoulder shot and more like a scope/sniper close-up on
the target alone.

**Finding 2 — the tween itself passes close enough to the shooter's body to glitch.** Because
`ease_to_attack_framing` interpolates `pan_offset` *linearly* from the current (distant,
tactical) camera position to the tight final position, the straight-line path swept close
enough to the shooter's own geometry partway through that the shooter's model visibly
ballooned to fill roughly half the screen for part of the transition, before shrinking back
down as the tween finished. Confirmed via a mid-tween screenshot (`_active_tween.custom_step(
ATTACK_TWEEN_DURATION * 0.5)`).

### Fix applied

Given two candidate fixes — (a) pull the final resting offsets back so the shooter's body has
real clearance, or (b) leave the final framing tight but change the tween's *path* (e.g. an
intermediate waypoint or a curve) so it never sweeps through the shooter — the offset pull-back
was chosen as the more contained change (one-line constant tune, no new interpolation
machinery).

`ATTACK_RIGHT_OFFSET: 0.9 → 2.5`, `ATTACK_UP_OFFSET: 0.6 → 1.5` (roughly 2.5x each).

**Verified improvement, not assumed:** re-ran the same before/mid/after screenshot sequence.
The mid-tween shooter silhouette dropped from roughly 27% to roughly 11% of frame width. At
rest, the camera-to-target sightline no longer passes anywhere near the shooter's torso
(checked numerically: the closest point on the sightline to the shooter's torso moved from
essentially coincident to several units away).

### Current status: still not right

After the pull-back, the camera was reported as **still "funky"** — improved by the numbers
above, but not resolved. The user is planning to investigate a deeper fix themselves; this
pass is paused pending that. Current constants remain
`ATTACK_RIGHT_OFFSET = 2.5, ATTACK_UP_OFFSET = 1.5, ATTACK_PITCH = -0.25` (fallback only, used
when shooter and target share a cell), `ATTACK_TORSO_HEIGHT = 1.25`,
`ATTACK_TWEEN_DURATION = 0.4`.

## Untried / candidate directions for the deeper fix

Not implemented — recorded here so they don't need re-deriving:

- **Tween path, not just the endpoint.** The pull-back reduced the mid-tween glitch but didn't
  eliminate the underlying cause: a straight-line `pan_offset` lerp between two very different
  camera regimes (far tactical orbit vs. close attack shot) has no guarantee of staying clear
  of anything in between. A path that eases height/distance out first, or arcs around instead
  of cutting through, would fix this at the source instead of relying on offset margin alone.
- **Show the shooter on purpose.** An over-the-shoulder camera in most third-person games
  keeps a visible sliver of the controlled character's own shoulder/weapon in the near
  foreground for context. The current model only prevents *occlusion* of the target; it makes
  no attempt to compose the shooter into the frame at all. Whether that's worth doing depends
  on what "over the shoulder" is actually supposed to communicate here.
- **Reconsider `ATTACK_TORSO_HEIGHT`/offset coupling.** Both offsets are currently flat
  constants applied identically regardless of shooter/target distance or relative height
  (e.g. shooting across an elevation change, once elevation exists). Not yet a problem on the
  current flat single-elevation grid, but worth revisiting if/when that changes.
- **Field of view.** Never touched this pass — `Camera3D` is using its default FOV throughout.
  A narrower FOV at close range would reduce how much the shooter's proximity distorts the
  frame in the first place, independent of position tuning.
