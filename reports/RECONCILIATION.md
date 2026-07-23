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

Next: Step 2, per-block content reconciliation, oldest first.
