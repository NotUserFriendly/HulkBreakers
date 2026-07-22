# SUPERSEDED.md — The Reversal Ledger

**Append-only historical record.** Every design decision that was true once and has since been
overwritten. Its job: keep an old note, comment, or commit that assumes the *former* shape from being
mistaken for current truth. Rarely edited — only appended when something is reversed.

For current state see `CHANGELOG.md`; for forward work see `PLAN.md`.

---

| Was | Now | Changed in |
|---|---|---|
| Slot-keyed `SlotType` / `Part.slot_type` | inverted attachment — parts declare `attaches_to`, sockets declare `socket_type` | early (pre-audit) |
| Exposure table / `exposure_weight` / `_weighted_choice` / `CoverInfo.profile` | continuous projection into the depth-sorted shot plane | early (pre-audit) |
| "robot" / "chassis" / "Frame" vocabulary | "cyborg / bot / shell"; `Frame` → `Shell` | early (pre-audit) |
| `resolve_projectile(plane, point)` — 2D plane lookup | `resolve_ray(muzzle, dir)`; the shot plane demoted to the aiming *window* | tb06 A / tb07 A |
| `cook_off()` + `VOLATILE` as the trigger | `failure_mode = DETONATE`; the tag is descriptive, the mode drives it | tb09 A3 |
| `BREAK` failure mode | deleted — a part leaves the body **only** via a severed joint, never its own failure | tb09 C2 |
| MANGLE detaches children / swaps to a wreckage item | MANGLE **stays attached**, keeps **¼ residual DT**, socket still hittable; a live two-stage state (`is_mangled`) | tb05 → revised tb09 A1 |
| Subtree-drop owned by part destruction | subtree-drop owned **entirely by joints** — lose the tree below a hit only when the *joint* is cut | tb09 C |
| DT is a flat `material.dt` lookup | DT is a **`dt_curve` table** per material, thickness-interpolated | tb09 E |
| `Part.recoil` (dead field) | deleted; recoil is **computed** (`RecoilResolver`, damage↑/barrel↓), widens the dartboard across a burst | tb13 D |
| `Part.damage` / gun-owned damage | damage lives on **`AmmoDef`**; the gun (`WeaponDef`) is a multiplier | tb10-ammo / tb13 A |
| Definitions hardcoded in `.gd` | all moved to **`.tres`** via `DataLibrary` (res:// builtin + user:// override, user wins) | tb10 |
| Cover as a cell scalar (`set_cover_value`) | cover is **placed field-object parts** that block movement and project into the shot plane | tb16 B |
| Bot facing: single face at end of move | **per-tile** facing — face each tile before stepping; interrupted move leaves you facing your travel direction | tb16 A |
| Battle and Bout as separate scenes | **one `BattleScene`**; control is a swappable **overlay** (squad / single-unit / spectator / generate-bout); `bout_view.gd` / `simulate_bout_menu.gd` retired | tb15 |
| Action ordering: facing is fastest (tb06) | overwatch fast, facing slow — an aimed-and-waiting overwatcher resolves before a reorienting unit; flip to lower-resolves-first | tb18 / tb19 A |
| "Lean" (the step-out mechanic) | renamed **Step Out** — "lean" reserved for a future literal-lean ability | tb19 B |
| `PowerResolver.max_ap_for` (simple power read) | surplus (output − consumers) → AP via a **diminishing `power_to_ap_curve`** | tb20 F → revised tb22 B |
| Extract ends the bout on the first unit out | **squad 0 must get its whole team off**; asymmetric extraction (red: 1-AP action; blue: hold the tile to end-of-next-round); empty enemy squad is not terminal | tb22 A |
| One guessed muzzle-to-impact tracer segment, pinned to a constant height | every shot/ricochet hop draws its own tracer at its real, logged point (tb22 D), fully 3D — no longer pinned to a constant height at all (tb23 D) | tb22 D → revised tb23 D |
| Flat `UISink` combat log (one line per event) | hierarchical fold at **render time only** (`LogFold`/`LogFoldGroup`/`HierarchicalUiSink`) into action-level, expandable summaries — the event stream itself untouched | tb22 F |
| `InventoryPanel` (always-visible left-column tree) as player view's inventory surface | deleted; **`InspectPanel`** is the one inventory surface in player view too, same as spectator | tb22 I |
| `BodyProjector` flattens every part's projection to one height plane (Y forced to 0) | real vertical extent retained — a head projects higher than a waist, a foot lower | tb23 A |
| `ShotPlane.resolve_ray` rejects any non-horizontal shot (`push_error` if `dir.y != 0`) | accepts a true 3D ray; a ricochet's reflected direction branches vertically too | tb23 C |
| Each squad's own spawn cells double as its own extraction tiles (teams never cross) | bout-setup places each side's extraction on the **opposing** side, forcing engagement | tb23 E1 |
| AI and the player's own UI hardcoded `AttackAction` regardless of what a weapon actually provides | firing action derived from the weapon's own `provides_actions` via `ActionCatalog.build_firing_action`, for both | tb24 A |
| Burst-only weapons enforced only as a UI convention (the action bar just never showed the button) | `is_legal` enforces `provides_actions` as a real engine rule | tb24 B |
| Overwatch was assignable but the AI never actually considered/chose it — a stranded mechanic | the AI weighs and can hold overwatch through the same catalog seam the player's own action bar reads | tb24 C |
| Step Out's own two automated legs cost real MP/AP, no discount ("the automation is in ASSEMBLY, not in cost") | both legs are free (`MoveAction.free`) — no MP/AP either direction, for the AI and the player alike | tb27 B2 |
| Every squad defaults to `HUMAN` ("Control All Squads"); `CombatState.controller_for()` falls back to HUMAN for any unset squad | `SquadController.UNASSIGNED` is the zero-default; a bout **hard-errors at construction** if any squad on the board is unassigned; control is set explicitly (`assign_all_to_human`/`assign_rest_to_ai`) — no silent gameplay default | tb31 B |
| Walls as **indestructible** terrain — "terrain is a Part flagged indestructible" (`docs/02`), the BR30.10 wall model (a `WALL`-terrain cell with an indestructible blocker) | a wall is **high-DT destructible cover** — a blocker `Part` on an otherwise-passable `OPEN` tile; negative space is a new `VOID` terrain fill; only the void past a wall is indestructible. (`Pathfinder` now also clears a destroyed blocker, walls and scatter cover alike) | BR30.10 → reversed tb31 C |
| `ActionDef.requires_target: bool` — two targeting shapes (board-target, or not) | `Enums.TargetingMode` (`BOARD`/`NONE`/`PART_PICKER`); the action bar dispatches by mode and overwatch/repair reach the bar directly instead of bolted-on overlay buttons | tb31 D |
| Active unit recolors its facing wedge/team marker to `ACTIVE_TURN_COLOR` (tb27 D2) | facing-marker-assembly **visibility** only — team marker + facing wedge toggle together for the active unit, no recolor at all; presence indicates whose turn it is, not color | BR27.07 → reversed tb32 D |
| Wall occlusion: one focal wall faded at a time via per-object GDScript alpha (`BoardView.WALL_FADE_ALPHA`/`_set_wall_alpha`, tb31 C, BR31.03) | per-fragment dithered `discard` shader cuts a screen-space porthole around **every** unit at once (`wall_cutout.gdshader`); GDScript only feeds uniforms, the shader owns the discard decision | tb31 C → reversed tb32 A |
| Friendly-blocks-aim fade drawn as a separate translucent ghost overlay next to the friendly (`BoardView._friendly_fade_overlay`, tb32 B first version) — left the friendly's own real `HitVolumeView` fully opaque underneath it | fades the friendly's own real body directly (`HitVolumeView.set_occlusion_faded()`), decision owned by `BattleScene._process()` | tb32 B (same-taskblock redesign, after live testing showed the first version unreadable) |
| `AttackAction`/`BurstAction.is_legal()` required a live target `Unit` at `target_cell` | also legal against a shootable non-unit `Part` (`Grid.shootable_part_at`) — cover, walls, downed bots, loose field items; melee actions (`Stab`/`Slash`/`Grind`) unchanged, still require a real Unit | tb32 C |
| **Checkpoint discipline** — five committed-artifact gates (`./checkpoint.sh N`) at foundation phases, each a hard stop for human review (a surviving v2.1 standing rule; `docs/09`) | retired — CC was told early to prefer clean reports over generated artifacts, so the ritual sat unused ~30 blocks; its review job is now done live (supervisor plays/bug-hunts in spectator/reviews docs) + tester-mode. `test_checkpoint_1–4.gd` survive as ordinary regression tests; checkpoint 5 retires with `test_full_mission` | tb31 review → tb32 |

---

## The retired plan
`PLAN.md` v2.1 and earlier described the from-scratch foundation build (Phase 0 harness, v1-survival
table, exposure-table deletion, the `los.gd` `range`-shadow bug fix). All shipped. The v2.1 plan is
fully retired. Of its two standing rules, only **enums-vs-open-data** survives into v3; the other,
**checkpoint discipline**, was itself later retired (see the ledger row below) once the from-scratch
foundation shipped and live supervisor review replaced the artifact gates.

## Overwatch resolves its own shot (observed tb28 — not yet changed)
**Was:** overwatch's `_fire` is a self-contained shot resolver — it builds its own shot plane, samples
the dartboard, and resolves damage/crit/pen directly, independent of the normal firing path. This was
the original intent when overwatch was built.
**Now (intended, not yet implemented):** overwatch should be a **trigger** that fires the unit's
*provided* firing action — burst preferentially, a shot as fallback — through the shared resolver, the
same way tb24 made the AI derive actions from `ActionCatalog`. The self-contained resolver is a
parallel system (violates the no-parallel-systems rule as it now stands) and it has inherited the
pre-tb27 cell-anchored origin/direction bug (the backward-shot class, cf. BR27.02).
**Status:** logged as a superseded design, **NOT changed yet** (supervisor's call). The eventual fix
replaces `_fire`'s bespoke resolution with "construct and resolve the weapon's provided firing
action." Until then, overwatch works but off the shared path. *(The inherited backward-shot symptom,
if/when it surfaces visually, is a BUG — file it separately; the parallel-path design itself is this
reversal, not a bug.)*
**tb31 D update:** overwatch got its first real UI call site (armable from the action bar via
`TargetingMode.NONE` → `ActionCatalog.build_untargeted_action` → `OverwatchAction`), so it's no longer
a stranded, UI-less mechanic — but `_fire`'s self-contained resolver is **still unchanged**. The
parallel-resolver reversal above remains pending; only reachability changed, not resolution.
