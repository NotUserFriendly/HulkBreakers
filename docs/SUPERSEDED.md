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

---

## The retired plan
`PLAN.md` v2.1 and earlier described the from-scratch foundation build (Phase 0 harness, v1-survival
table, exposure-table deletion, the `los.gd` `range`-shadow bug fix). All shipped. The v2.1 plan is
fully retired; only its two standing rules (enums-vs-open-data, checkpoint discipline) survive into
v3.
