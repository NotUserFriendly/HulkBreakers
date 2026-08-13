#!/usr/bin/env python3
"""taskblock-68 Pass B — write the `outcome` and `evidence` columns of the fixture census.

    python3 audit/classify_fixtures.py            # writes audit/fixture_census.csv in place
    python3 audit/classify_fixtures.py --check    # prints the counts, writes nothing

`outcome` is a judgement column, the same kind as `rule_guarded` on `suite_audit.csv`. It is
written by a script rather than by hand for one reason: **192 rows classified by hand is 192
opportunities to be inconsistent, and nobody can review the result.** What is reviewable is a
short rule plus a list of the rows that are exceptions to it — so that is the shape here.

## The rule

Applied to every file that calls `Part.new()`; files that never do are not fixtures and get no
outcome at all.

- **`no_unit`** -> `CORRECT`. The file never constructs a `Unit`, so no body structure exists for
  a fixture to have got wrong. `Part`s here are inputs to a rule about parts.
- **`real_unit`** -> `CORRECT`. Units come off the game's own assembly path; hand-built `Part`s
  are inputs to the assembler *under test*. `test_body_assembler.gd` is the model and says so in
  its own header.
- **`hand_built`** -> the candidate set, and the rule stops here. Its default is `CORRECT` when
  nothing in the file's assertions can see a body's structure, and every departure from that is
  an entry in `EXCEPTIONS` with its evidence.

## Where the evidence comes from

Three instruments, all committed:

- `fixture_census.csv` — `shape`, and `conflicts`.
- `fixture_conflicts.csv` — the borrowed-id disagreements, one row per field.
- `substitution_probe.jsonl` — what happened when the real chaingunner was put through the
  file's own fixture helper.

**None of the three decides anything on its own.** A probe failure is usually the instrument (see
that script's header); a conflict is usually a label. The `EXCEPTIONS` table below is where a
human reading of those three is recorded, one line of evidence per row.
"""
import csv
import json
import sys

CENSUS = "audit/fixture_census.csv"
PROBE = "audit/substitution_probe.jsonl"

BULK = {
    "no_unit": (
        "CORRECT",
        "never constructs a Unit — the rule is below the level where a body has structure",
    ),
    "real_unit": (
        "CORRECT",
        "units come off the game's own assembly path; hand-built Parts are inputs to it",
    ),
    "hand_built": (
        "CORRECT",
        "hand-built body, but nothing the file asserts can see a body's structure",
    ),
}

# origin_file -> (outcome, evidence). Filled from reading, with the instrument that pointed there.
#
# ## The line between a `DRIFTED` row and an instrument artefact
#
# The taskblock's table reads "substituted run fails -> DRIFTED", and taken literally that makes
# almost every red probe a finding, because the substitution drops the helper's parameters and
# swaps the weapon under the test. The line actually drawn here, and it is stated so it can be
# argued with:
#
#   **A broken assertion is `DRIFTED` when it is a claim about the game. It is an artefact when
#   it is a restatement of the fixture's own inputs.**
#
# `assert_eq(rows.size(), 3)` where 3 is the number of parts the fixture just authored restates an
# input — it would be equally true of any fixture, and it says nothing about the game. But
# `assert_eq(real_hit.part.id, &"wall", "the real plane really does resolve to the wall")` is a
# claim about how the game resolves a shot, and a real shell contradicts it.
EXCEPTIONS = {
    # --- DRIFTED -------------------------------------------------------------------------------
    "unit/logic/test_line_of_fire.gd": (
        "DRIFTED",
        "its oracle excludes shooter.shell.all_parts(); every production path "
        "(ShotResolution, AimController, Overwatch) excludes all_parts_with_joints() per BR36.01. "
        "The two are identical for this file's socket-less torso, so the divergence is invisible; "
        "under a real 48-box shell the plane resolves to the shooter's OWN ammo_rack_joint "
        "instead of the wall (substitution probe). The file's header asks for exactly the "
        "opposite: 'read the actual plane back, don't re-derive the ray math'",
    ),
    "unit/logic/test_detonation_draw.gd": (
        "DRIFTED",
        "asserts radius 3.0 as 'the part's own real radius' on a hand-built goo_barrel; the "
        "game's goo_barrel is radius 2.0, detonate_damage 12.0 not 40.0, material reactive not "
        "steel (fixture_conflicts.csv). The rule — the drawn radius is a readout of what resolved "
        "— is still guarded; the sentence claiming the number is the game's is what is false",
    ),
    # --- AVOIDING ------------------------------------------------------------------------------
    "unit/logic/test_inspect_rows.gd": (
        "AVOIDING",
        "a real shell produces 26 rows against this fixture's 3, so the weapons/containers/body "
        "partition is only ever exercised with one member per group. The ordering assertions "
        "survive the substitution; only the hardcoded row count does not",
    ),
    "unit/logic/test_inventory_rows.gd": (
        "AVOIDING",
        "a real shell produces 26 rows against this fixture's 1, so the socket/contents nesting "
        "rule this file exists for is only ever tested at depth 0-1",
    ),
    "unit/view/test_hit_volume_view_mesh_scene.gd": (
        "AVOIDING",
        "its assertion reads 'no box instance may exist for a part that has a commissioned mesh' "
        "and actually checks that NO box instance exists anywhere in the view — identical claims "
        "for a one-part fixture, and a real shell separates them. The per-part rule is genuinely "
        "covered by test_a_mixed_assembly_renders_the_mesh_and_the_box_together",
    ),
    # --- CORRECT, but read individually and worth the sentence --------------------------------
    "unit/logic/test_penetration_traverses_body.gd": (
        "CORRECT",
        "same pre-BR36.01 all_parts() exclusion list as test_line_of_fire.gd, but inert here: the "
        "shooter is Shell.new(Part.new()), a deliberately geometry-free placeholder with no "
        "sockets, so the joint-bearing half of the list is empty either way",
    ),
    "unit/logic/test_internal_targeting.gd": (
        "CORRECT",
        "same pre-BR36.01 all_parts() exclusion list, also inert: the shooter is a bare "
        "DataLibrary torso whose sockets are unoccupied, and walk_with_joints emits a joint only "
        "for an OCCUPIED socket. Builds its fixture from real parts throughout",
    ),
    "unit/logic/test_seam_sweep.gd": (
        "CORRECT",
        "the shooter is excluded from its own shot and the ray's origin is passed in explicitly, "
        "so no property of the body can reach the measurement; a real 48-box shell passes it "
        "unchanged. Uses all_parts_with_joints(), which is the list production uses",
    ),
    "unit/logic/test_step_height.gd": (
        "CORRECT",
        "the rule is how step height VARIES with leg geometry, so the fixture has to vary — one "
        "real unit is one sample, and the assertions are relative to each fixture's own legs",
    ),
    "unit/logic/ai/test_bout_runner.gd": (
        "CORRECT",
        "the rifle's ap_cost 5 against the real 2 is deliberate and the fixture says so: it makes "
        "a plain shot unaffordable against the unit's own 3 max_ap, so overwatch is the only "
        "option the turn has. A real weapon would remove the thing under test",
    ),
    "unit/logic/test_damage_resolver_consequences.gd": (
        "CORRECT",
        "the arm's failure_mode DISABLE against the real MANGLE is the second of a matched pair — "
        "the file asserts MANGLE is the default in one test and sets DISABLE in the next to "
        "exercise the other branch",
    ),
    "unit/logic/test_data_validator.gd": (
        "CORRECT",
        "the reactor's failure_mode NOT_A_REAL_MODE is the input the validator exists to reject; "
        "a valid value would test nothing",
    ),
    "unit/logic/test_repair_resolver.gd": (
        "CORRECT",
        "the leg's material steel against the real artificial_bone reaches nothing: scrap cost is "
        "heal_amount * SCRAP_PER_HP with no material term, and the one test that does care sets "
        "its own ceramic and asserts the passthrough",
    ),
    "unit/logic/test_shot_plane.gd": (
        "CORRECT",
        "fixtures authored symmetric about x == 0, the line of fire, because that is the natural "
        "body-space origin for the depth-sort rule under test — its own header says so",
    ),
    "unit/logic/test_body_assembler.gd": (
        "CORRECT",
        "the model case, and its header already said so before this audit: the reference "
        "humanoid's structural correctness is covered by test_reference_humanoid.gd, and these "
        "tests exercise the assembler's contract with purpose-built fixtures",
    ),
}


def probe_verdicts():
    try:
        rows = [json.loads(line) for line in open(PROBE)]
    except FileNotFoundError:
        return {}
    # A record without a `substituted` verdict is a file the probe did not measure — skipped as
    # its own instrument, or interrupted. It contributes no evidence either way.
    return {
        r["file"].replace("test/", ""): r for r in rows if r.get("substituted")
    }


def main():
    check = "--check" in sys.argv
    with open(CENSUS, newline="") as handle:
        reader = csv.DictReader(handle)
        names = reader.fieldnames
        rows = list(reader)

    probes = probe_verdicts()
    counts = {"CORRECT": 0, "AVOIDING": 0, "DRIFTED": 0, "": 0}
    for row in rows:
        if row["part_new"] == "0":
            row["outcome"], row["evidence"] = "", ""
        elif row["origin_file"] in EXCEPTIONS:
            row["outcome"], row["evidence"] = EXCEPTIONS[row["origin_file"]]
        else:
            row["outcome"], row["evidence"] = BULK[row["shape"]]
            probe = probes.get(row["origin_file"])
            if probe and probe["substituted"] == "pass":
                row["evidence"] += "; a real 48-box shell through its own helper passes unchanged"
        counts[row["outcome"]] = counts.get(row["outcome"], 0) + 1

    for outcome in ("CORRECT", "AVOIDING", "DRIFTED"):
        print(f"{counts.get(outcome, 0):5d}  {outcome}")
    print(f"{counts.get('', 0):5d}  (not a fixture — no Part.new())")

    if check:
        return
    with open(CENSUS, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=names, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {CENSUS}")


if __name__ == "__main__":
    main()
