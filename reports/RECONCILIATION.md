# Taskblock / report / living-doc reconciliation

One-time audit (`cc-task-doc-reconciliation.md`), not a taskblock. Gates two decisions: purging
`taskblock_done/` (specs back to tb12) and moving reports to the rolling five-report window in
`reports/`. Neither is safe until this says nothing lives *only* in those files.

Taskblock specs exist back to `taskblock04.md`, but no report exists before `Report-Taskblock12.md` —
this audit's own scope (per the task) starts at tb12; tb04–tb11 are pre-existing, spec-only, and out
of scope here (flagged, not audited).

## Step 1 — Inventory

| tb | spec present? | report present? | notes |
|----|----------------|------------------|-------|
| 12 | yes | yes | — |
| 13 | yes | yes | — |
| 14 | yes | yes | — |
| 15 | yes | yes | — |
| 16 | yes | yes | — |
| 17 | yes | yes | — |
| 17-1 | yes | yes | Deliberate sub-numbered interstitial ("blockers for 18/19"), not an anomaly — both its own spec and report exist. |
| 18 | yes | yes | — |
| 19 | yes | yes | — |
| 20 | yes | yes | Report title ("The Body Is A Layered Target") differs from the spec title ("Layered Bodies: Cladding, Skeleton, Organs, Coring, Reactions") — same block, no numbering issue. |
| 21 | yes | yes | — |
| 22 | yes | yes | Report title lists more sub-features than the spec title — same block (spec itself says "a big block"), not multiple blocks combined. |
| 23 | yes | yes | — |
| 24 | yes | yes | — |
| 25 | yes | **no** | **Anomaly.** No `Report-Taskblock25.md` ever existed. The shipped system (Melee, keystone 1) reached `docs/CHANGELOG.md`/`docs/PLAN.md` under "tb25" provenance regardless — confirmed by grep — but no report-level record (decisions made unasked, corrected tests, pending digest) exists anywhere. Step 2 must read the spec alone and check bugs/reversals/deferred items landed. |
| 26 | yes | yes | — |
| 27 | yes | yes | — |
| 28 | yes | **no** | **Anomaly.** No `Report-Taskblock28.md` ever existed. Shipped systems (seeded variant generation, kits/instant-equip) confirmed present in `docs/CHANGELOG.md` under "tb28" provenance; one bug (`docs/SUPERSEDED.md`... see `docs/BUGS-ARCHIVE.md`, "observed tb28 — not yet changed") also present. No report-level record exists. |
| 29 | yes | **no** | **Anomaly.** No `Report-Taskblock29.md` ever existed. Shipped system (bout injection, `BoutInjector`) confirmed present in `docs/CHANGELOG.md`/`docs/PLAN.md` under "tb29" provenance. No report-level record exists. |
| 30 | yes | yes | **Known anomaly, already resolved correctly.** tb30's own spec (`taskblock30.md:51`) documents "Rolled in from taskblock31 (never its own block — still tb30): Debug Control Panel" — an originally-planned "taskblock31" (Debug Control Panel) was absorbed into tb30's own rolling bug pass and never got its own spec/report under that name. Confirmed: `docs/CHANGELOG.md` already credits this correctly ("Debug control panel (tb30, rolled in from a planned tb31)") — content is not lost, just worth flagging so a future reader doesn't expect a standalone tb31-Debug-Panel spec that never existed. |
| 31 | yes | yes | The number 31 was **reused**: this spec/report pair ("View & Control Consolidation") is a real, later, unrelated block — not the same as the informal "taskblock31" rolled into tb30 above. Two different things share the number 31 across this project's history; only the later one has a real spec/report. |
| 32 | yes | yes | — |
| 33 | yes | yes | — |
| 34 | yes | yes | — |
| 35 | yes | yes | This session's own taskblock. |

**Summary: 3 real gaps (tb25, tb28, tb29 — spec present, no report ever written), 1 already-resolved
naming anomaly (tb30/31 number reuse, correctly attributed in CHANGELOG already), 1 non-anomalous
sub-numbering (17-1). No gap in the numbering itself (04 through 35 is continuous once 17-1 is read
as a deliberate interstitial), no report was found covering more than one distinct block.**

## Step 2 — Per-block content reconciliation

Worked oldest-first. Each entry: what was already covered, what was missing, what was added and
where.

### tb12 — Test Suite Cleanup

**Missing, now added.** This block had zero footprint in any living doc. Pass A (measured the
suite directly rather than assuming — only 3 genuine same-setup clusters existed, not the ~394→~120
estimate) and Pass B/C (audited `test_body_projector.gd`/`test_damage_resolver.gd`/
`test_data_migration_losslessness.gd` against the live model and found them current, one redundant
pair folded) are both exactly the "audited and found correct"/"assumed premise didn't hold"
categories this reconciliation exists to catch. Added a new paragraph to `docs/CHANGELOG.md`'s
"Tooling, data & view" section, between "Data layer" and "View".

### tb13 — Weapons: Cartridges, Burst, Recoil, Spread, Ricochet Plates

**Partially missing, now added.** The `WeaponDef`/`AmmoDef` split, cartridges, burst, and recoil were
already covered (`CHANGELOG.md`/`SUPERSEDED.md`). Missing: Pass F (per-part display-name `Label3D`)
and Pass G (wedge/cylinder ricochet plates, shipped as a test fixture not content) had no trace, nor
did two bugs found and fixed mid-pass in code still current today (`test_battle_scene.gd`'s stale
mesh-transform-equals-hitbox assumption, broken by `render_scale`; `DataLibrary.get_ammo`'s
always-fresh-duplicate silently defeating a fixture mutation). Appended to the end of the "Armor,
damage & weapons" entry in `docs/CHANGELOG.md`.

### tb14 — Bot Profiles, an AI Module, and Watchable Bouts

**Partially missing, now added.** `UnitAI.plan_turn`/playstyles and the watch-loop/menu were already
covered. Missing: Pass A's entire named-bot-profile mechanism (`BotPreset.profile_family`/
`variant_label`, `DataLibrary.TYPE_PRESETS`, the deliberate two-coexisting-persistence-paths
decision) had zero trace. Inserted into the existing "Bouts (tb14)" `docs/CHANGELOG.md` entry.
Pass C/D's own found-and-fixed bugs live in `bout_view.gd`/`simulate_bout_menu.gd`, both **retired
entirely by tb15** (confirmed: zero hits in `src/` today) — correctly not documented, since the code
they describe no longer exists.

### tb15 — One Battle Scene, Swappable Control Overlays, Playback Animation

**Nearly complete, one addition.** The overlay/animation consolidation was already thoroughly
covered. Missing: a real ordering bug found and fixed in code still current
(`BattleScene._ready()` used to call `new_battle()`, emitting the session-start log line, before any
overlay/log-sink existed to catch it). Appended to the "View" entry in `docs/CHANGELOG.md`.

### tb16-19 — pending (see below, inserted out of arrival order; audit was still running when this
section was first assembled)

### tb20 — Layered Bodies: Cladding, Skeleton, Organs, Coring, Reactions

**Nearly complete, one addition.** All passes A-F/H were already covered in the "Layered bodies &
power" `CHANGELOG.md` entry. Missing: Pass G (confirm-only — audited that internal-targeting shots
already run through tb19's range-accuracy pipeline unbypassed) — the clearest "audited and found
correct" case in this block. Appended to the "Range" entry in `docs/CHANGELOG.md`.

### tb21 — The Inspect Panel, Bout Control, Flee/Extraction, and Cleanup

**Partially missing, now added.** Inspect panel, spectator click-to-inspect, flee/extraction were
covered. Missing: Pass E's FPS-hitch investigation (three measured, unfixed costs — the log-sink
full-text-reassignment pattern, `HitVolumeView.refresh()`'s full rebuild, turn-start power recompute
re-walking the part graph) had zero trace, and is explicitly deferred/investigation-only work,
confirmed still-live today (the same reassignment pattern lives on unchanged in tb22 F's
`HierarchicalUiSink`). Added to `docs/PLAN.md`'s "Support & remaining combat gaps".

### tb22 — Extraction, Power→AP, Shutdown, Every-Shot Visibility, Repair, Log

**Partially missing, now added.** Extraction, power/AP, shutdown, tracer visibility, the
hierarchical log were all covered. Missing: (1) Repair's own "partial win" nature — logically
complete and tested but not reachable in natural gameplay (no part's `salvage_yield` produces the
`material`-namespace scrap it reads) — the existing CHANGELOG entry read as if it simply shipped,
dropping this caveat; appended the honest partial-win statement. (2) Pass H's "two parallel
shot-geometry systems, never unified" architectural finding had no trace; added to `docs/PLAN.md`'s
"Support & remaining combat gaps".

### tb23 — True-3D Shot Resolution (a bugfix that founds multi-level)

**Partially missing, now added.** Passes A-E were covered in CHANGELOG/SUPERSEDED/BUGS-ARCHIVE
(BR22.01). Missing: (1) `docs/PLAN.md`'s own "Block 1" section still described this shipped
foundation as unbuilt forward work — trimmed to a one-paragraph "SHIPPED" note, Block 2 (genuinely
still unbuilt) left as-is. (2) A real memory leak found and fixed in Pass E2 (a full `WorldEnvironment`
node allocated and never freed on every `InspectPanel` construction, just to steal its `.environment`
resource) had no ledger entry — added as `BR23.01 — Resolved — owner: CC` in `docs/BUGS-ARCHIVE.md`.
(3) `BodyProjector`'s flagged "no top/bottom faces" limitation had no home — added to `docs/PLAN.md`'s
"Support & remaining combat gaps".

### tb24 — The AI Derives Its Actions From `provides_actions`

**Partially missing, now added.** The catalog-driven action derivation and its three passes were
covered. Missing: three real bugs found and fixed along the way, none previously logged anywhere —
(1) the player could never queue `BurstAction` either (`confirm_shot` hardcoded `AttackAction`,
grepped and confirmed `BurstAction` was never constructed anywhere in `src/view/` before this fix);
(2) overwatch was structurally unable to trigger for any normally-bodied unit (`Overwatch.
_torso_visible`'s own ray never excluded the overwatcher's own torso — every test fixture masked this
by building a torso-less overwatcher); (3) overwatch was never even checked during any AI-vs-AI bout
(`BoutRunner.step()` never wired a `mid_move_hook`). Added as `BR24.01`/`BR24.02`/`BR24.03` —
Resolved, owner CC — in `docs/BUGS-ARCHIVE.md`. Also added the deferred "AI repair" design note to
`docs/PLAN.md`.

### tb25 — Melee (keystone 1) — no report, spec-vs-living-docs only

**Partially missing, now added; some content permanently unverifiable.** Every pass's own mechanism
(delivery, resolution reuse, the three payloads, the spherecast, un-stubbed suppression, the punch,
playstyles) was already present in CHANGELOG's "Melee (tb25, keystone 1)" entry, closely matching the
spec. Missing: `docs/PLAN.md`'s own "Phase M" keystone header still read as entirely unbuilt forward
work despite everything having shipped — trimmed to a "SHIPPED" note plus the two pieces genuinely
still open (Protector playstyle, the `POWER`/`TRIGGER` weapon-distinction capability split), both of
which the original section already named. **Because no report was ever written for tb25, this is a
permanent blind spot, not a resolved gap:** whether any bugs were found, any approach was tried and
reverted, or any decision was made without asking during this block cannot be recovered now — flagged
honestly rather than assumed clean.

### tb26 — Melee Follow-up: Fixes, Joint Depth, Tile Inspector

**Nothing missing — reconciles cleanly.** All three Pass A bugs, the teleport fix, the skirmisher-
freeze partial win (16/60→8/60, stated honestly as partial), the bout-maker/menu/inspect-header
fixes, joint HP/cladding, the tile inspector, every scope-fence deferral, and the CC-found stab
slide-deflect bug are all present with full detail across `CHANGELOG.md`/`SUPERSEDED.md`/`BUGS.md`/
`BUGS-ARCHIVE.md`/`PLAN.md`.

### tb27 — Bug Consolidation Pass

**Nothing missing — reconciles cleanly.** Pass A (muzzle/direction anchor unification), Pass B
(Step Out, the `MoveAction.free` reversal), Pass C (skirmisher mechanism, the z-fight ladder audit
that found a previously-unchecked co-planar pair), and Pass D's whole bug list (archived, still
open, or reclassified into CHANGELOG/PLAN as appropriate) are all fully present.

### tb28 — Tester Mode: Variants, Kits, and Combat Visibility — no report, spec-vs-living-docs only

**Shipped systems confirmed present; some content permanently unverifiable.** Seeded variant
generation (Pass A), kits/instant-equip (Pass B), and combat-log shot geometry in text (Pass C) are
all in `docs/CHANGELOG.md` under correct "tb28" provenance. **Because no report exists, whether tb28
found any other bugs, reversed any decision, or hit a dead end beyond these three shipped systems is
unrecoverable** — flagged as a permanent blind spot.

### tb29 — Bout Injection: Force Live State for Testing — no report, spec-vs-living-docs only

**Shipped systems confirmed present; some content permanently unverifiable.** The injection channel,
its verbs, the determinism/safety guards (`was_injected`, debug-gating), and the spectator hook are
all in `docs/CHANGELOG.md` under correct "tb29" provenance, plus tb30's own follow-up hardening.
**Because no report exists, the same permanent-blind-spot caveat as tb28 applies.**

### tb30 — Rolling Bug Pass (open-ended, supervisor-driven)

**Partially missing, now added.** The bulk of this large, open-ended block (BR27.05/06/09/11,
injection reaching player bouts, the Debug Control Panel and its many follow-ups, the BR30.10 wall/
shot-plane fix, BR30.09's reclassification, the `test_full_mission.gd` retirement decision) was
already thoroughly covered, including the harder "partial win"/"audited and found correct" categories.
Missing, both now added to `docs/CHANGELOG.md`: (1) a genuine "tried and reverted" episode — a raw
`SceneTree` driver script written to reproduce BR27.06 outside the headless suite crashed Godot via a
stale class reference (`UnitView` → `HitVolumeView`), revealing that `BoutInjector` is deliberately
gated out of player-controlled bouts and that the correct non-headless step for a player-input bug is
the real game, not a bespoke driver; (2) a debug-panel anchor bug (no anchor set at all, defaulted to
the top-left, overlapping the pre-existing HUD row), fixed with `_center_top()` plus a
`size_changed` handler.

### tb31 — View & Control Consolidation

**Nothing missing — reconciles cleanly.** All four passes (`UNASSIGNED` squad-control state,
`TopLeftControls` consolidation plus the found `mouse_filter` bug, the wall-as-destructible-cover-Part
model with its full defect chain, `TargetingMode` promotion) are fully present across
`CHANGELOG.md`/`SUPERSEDED.md`/`BUGS-ARCHIVE.md`. The Pass A audit table is correctly NOT duplicated
into a living doc — the spec itself scopes it as report-only.

### tb32 — View & Targeting

**Nothing missing — reconciles cleanly, most thoroughly cross-referenced block audited.** All four
passes, all four design reversals, and every bug (including the "tried and reverted" Y-flip theory
inside BR32.02, and the BR27.08 Tree→button reversal) are fully present.

### tb33 — AI: line of fire, not line of sight

**Partially missing, now added.** Pass A/B content, both reversals (LOS→LOF, greedy-reposition→
approach-fallback), BR32.10, and the BR30.10 partial-win follow-up were covered. Missing: the spec's
own scope fence explicitly deferred the player-facing sibling of the bug this block fixed for the AI
(`AttackAction`/`BurstAction.is_legal()` still gates on `LoS.has_los`, confirmed still true) to "its
own later pass" — had no trace anywhere. Added to `docs/PLAN.md`'s "Support & remaining combat gaps".

### tb34 — Aim view: truth & legibility

**Partially missing, now added.** All five passes, BR26.02, BR27.02's new angle, BR34.01, and BR33.01
(explicitly deferred to a supervisor policy call, per the spec's own scope fence) were covered.
Missing: the spec's own scope fence explicitly deferred "enemy-produced dartboards / an AI aim beat"
(naming `ShotScatter.for_shot`, tb34's own new primitive, as its prerequisite) to `docs/PLAN.md` — had
no trace anywhere. Added to `docs/PLAN.md`'s "Support & remaining combat gaps".

### tb35 — The wall-model audit, and the AI that stopped acting

**Nothing missing — reconciles cleanly.** This session's own taskblock; the report was written with
this exact migration discipline already applied in real time, before this reconciliation task existed.
Verified directly against the task's own three calibration examples:
- The reverted greedy-distance-scorer approach (Pass A, `closing_path`): present in `docs/CHANGELOG.md`
  ("deliberately not a greedy per-turn distance scorer (reproduces BR32.10's own concave-wall freeze;
  real A* just routes around)").
- The partial win (Pass A3, LOF memoisation): present in `docs/CHANGELOG.md` ("2023ms → 974ms... not a
  full fix for BR27.09").
- The audited-and-correct sweep (Pass C, `is Unit`/`Grid.blockers`): present in `docs/CHANGELOG.md`
  ("Audited and found correct as-is...") with per-site reasoning.

All bugs (BR34.06/BR27.02 fixed and archived since; BR32.01/03 fixed and archived since; BR34.05,
BR27.09, BR32.04, BR32.10 root-caused/improved and left open; BR35.01-06 new findings) are present in
`docs/BUGS.md`/`docs/BUGS-ARCHIVE.md`. No design reversal from this block needed a `SUPERSEDED.md`
entry (the depth-floor fix and wall-cutout fix were bug fixes, not reversed design decisions).
