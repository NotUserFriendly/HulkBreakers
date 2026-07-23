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

### tb16 — Per-Tile Facing, AI Ranges, Cover-as-Objects, Bout & Map Tuning

**Partially missing, now added.** Cover-as-objects/per-tile-facing reversals, field objects, AI
preferred ranges, and the melee-playstyle deferral were already covered. Missing: (1) per-tile
facing itself was never described as a shipped capability (only its reversal recorded) — added to
the Combat structure & AI section of `docs/CHANGELOG.md`. (2) Map generation tuning (Pass C) had zero
trace — added to the Bouts paragraph, combined with tb17 A's own grid-size fix (same underlying
story, one entry). (3) The bout menu's per-bot AI dropdown + duplicate/remove (Pass E) — folded into
the same Bouts-paragraph edit alongside tb17 D. (4) Three real bugs found and fixed mid-pass with no
ledger line (a cover/spawn-zone collision, an unseeded-RNG fallback corridor, a corridor-widening
that could erase a spawn tag) — added as `BR16.01`-`BR16.03`, Resolved, owner CC, in
`docs/BUGS-ARCHIVE.md`.

### tb17 — Spectator Fixes, Map Regression, Bout Menu, Plate Geometry

**Mostly missing, now added — the worst-reconciled block of the whole audit.** None of the five
passes had any prior citation anywhere. Added: (1) the map-generation regression itself (folded into
tb16's own CHANGELOG entry above) plus its own bug-ledger entry, `BR17.01`, Resolved/CC, in
`docs/BUGS-ARCHIVE.md`. (2) A real facing-error bug (up to 180° off target, not a flat 90°) — added
as `BR17.02`, Resolved/CC. (3) Two real design reversals with no trace — the spectator hover-inspect
mechanism swap (a full `TacticsController` stack replaced by a raycast + panel, itself later
reversed again at tb21 B) and the spectator auto-snap-camera removal — both added to
`docs/SUPERSEDED.md`. (4) The bout-menu per-bot-AI/duplicate feature (Pass D) — folded into tb16's
own CHANGELOG edit above (same feature, split across two taskblocks' own passes). Pass E's plate-
geometry corrections have no trace anywhere, matching this codebase's own established precedent of
not documenting test-fixture-only content (the original tb13 G rig they correct also has none) — not
flagged as a gap.

### tb17-1 — Blockers for 18/19

**Nearly complete, one addition.** Pass B (AI friendly-fire safety) and Pass C (reachability-aware
targeting) were already folded into the existing AI paragraph. Missing: Pass A found
`CombatState.round_number` already fully correct and needed no code change — a clean "audited and
found already correct" case with zero prior mention despite tb19 F (Hold) depending on the concept.
Added as a new "Round" clause in `docs/CHANGELOG.md`'s Combat structure & AI section. Pass D's own
"per-tile facing already correct, no changes" is a third confirmation of a fact already in
`docs/SUPERSEDED.md` — added no new information, correctly not re-recorded.

### tb18 — Resolution Speed: Initiative, Simultaneity, Interrupts, and Leans

**Partially missing, now added.** Passes A-D, the speed-direction reversal, and the perk-hook
deferrals were covered. Missing: (1) "equal-speed simultaneity" was stated as complete when the
report is explicit it's a logic-level-only query (playback still steps through units one at a time;
skipping the pause is a flagged, unbuilt follow-up) — exactly the "partial win rounded up to
complete" the CHANGELOG header warns against; corrected in place, not added alongside. (2) A real
"ghost bullet" bug found while writing the step-out interrupt test — a single-step move (exactly
what a step-out leg always is) could trigger overwatch, spend it, and still complete the queue,
latent since tb06 Pass F — added as `BR18.01`, Resolved/CC, in `docs/BUGS-ARCHIVE.md`.

### tb19 — Combat Corrections, Range, Visible Overwatch, Suppression, Hold

**Partially missing, now added.** The speed re-rank, Lean→Step-Out rename, range model, visible
overwatch, and the reaction-window deferral were covered. Missing, all added to
`docs/CHANGELOG.md`: (1) the Hold action (Pass F) was never actually described, only named in
passing — added alongside tb17-1's Round entry. (2) Suppression's real mechanic (a two-handed weapon
illegal while adjacent to a living enemy; leaving adjacency draws a free melee attack) was named but
never explained — the existing sentence was edited in place. (3) Pass H, audited-and-found-not-a-bug
(the suspected burst-fire code path never existed; a 200-seed sweep confirmed every pull always
fires — the reported symptom is the chaingun's own wide scatter, a data fact not a code bug) —
added to the weapons entry. (4) Pass J, audited-and-found-already-correct (headless vs. watched
bouts already share one `BoutRunner` path, no merge needed) — added to the Bouts paragraph. (5) Two
real playback performance fixes (a per-frame linear-scan lookup on every tween callback; a
triple-redundant full mesh-subtree rebuild per player turn) — added to the View paragraph. Pass G
(plate rebuilds) and I3 (weapon-label decals) have no trace anywhere, matching the same
test-fixture/cosmetic-polish precedent already established for tb13/tb17 — not flagged as gaps.

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

## Step 3 — Citations pointing at files that are going away

All six confirmed and fixed — each replaced with the fact it was pointing at, not repointed to
another file:
- `docs/BUGS.md`'s own preamble (was citing `taskblock_done/` generally as where acceptance criteria
  stay readable) — reworded: the durable record is this ledger and `docs/BUGS-ARCHIVE.md` now,
  regardless of whether the originating spec/report is still on disk.
- `docs/BUGS.md`'s BR27.03 entry (cited `Report-Taskblock27.md` for a correction note) — the fact
  (Pass A2's premise was wrong, not the bug) was already stated inline; citation removed, no
  information lost.
- `docs/PLAN.md`'s AI-target-fixation entry (cited `Report-Taskblock33.md`'s own follow-up) — folded
  in the actual measurement it was pointing at (zero impacts in 400 turns, the specific defender,
  the BR30.10 connection).
- `docs/BUGS-ARCHIVE.md`'s BR31.02 entry (cited `Report-Taskblock31.md` alongside CHANGELOG) —
  CHANGELOG already has the fix description in full; citation to the report removed.
- `docs/BUGS-ARCHIVE.md`'s BR32.02 entry (cited `Report-Taskblock32.md` for the over-cutting
  candidate cause) — that same finding already has its own tracked entry, `BR32.05`, in
  `docs/BUGS.md`; repointed there instead of the report.
- `docs/BUGS-ARCHIVE.md`'s legacy BR11.01 entry (cited the tb11 spec's own on-disk presence as part
  of why the bug recurred) — reworded so the explanation holds regardless of whether the spec is
  still on disk.

Re-grepped `taskblock_done`/`Report-Taskblock` across the whole repo after: zero remain outside
`reports/` (where this file and `reports/README.md`'s own naming-convention example are expected).

## Step 4 — CHANGELOG banner

`docs/CHANGELOG.md`'s own banner updated from *"Current as of taskblock-32 landed"* to *"Current as
of taskblock-35 landed"* (three blocks stale, now current). The task's own instruction to treat this
banner as part of CLAUDE.md's rule 8 from here on is a `CLAUDE.md` edit — that file is gitignored and
supervisor-maintained, not something this session edits directly; flagging it here for the
supervisor to fold in when convenient, rather than editing it unasked.

## Deliverable checklist

- [x] Step 1 inventory table (tb12-35, all anomalies flagged)
- [x] Step 2 per-block gap record, oldest-first, real content migrated where found missing, clean
      blocks recorded as clean
- [x] Step 3 confirmation — zero citations to `taskblock_done`/`Report-TaskblockN` remain outside
      `reports/`
- [x] Step 4 — CHANGELOG banner refreshed
- [x] All living-doc additions committed alongside this file, per step

**Bottom line for the purge decision:** `taskblock_done/`'s specs (tb12-35) are safe to purge — every
piece of durable content this audit could verify already has a home in a living doc. The one
irreducible exception is tb25/tb28/tb29's own missing reports: no amount of migration can recover
design decisions, tried-and-reverted approaches, or self-found bugs that were never written into a
report that no longer exists — those three blocks' own spec-vs-CHANGELOG reconciliation is as
complete as it can ever be, and what's missing beyond that is unrecoverable, not unfound. Reports
moving to the five-report rolling window in `reports/` is also safe under the same logic, going
forward, now that the discipline of migrating the three new categories out of a report and into a
living doc before it ages out is established.
