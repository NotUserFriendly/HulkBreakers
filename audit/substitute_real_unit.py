#!/usr/bin/env python3
"""taskblock-68 Pass B — put the real chaingunner through a candidate and see what breaks.

    python3 audit/substitute_real_unit.py <file-list>       # one test path per line
    python3 audit/substitute_real_unit.py --files a.gd b.gd

`PLAN`'s own sentence for this block: *"The detector is cheap: put a real chaingunner through
every test that simplifies a unit and see what breaks. A fixture that only passes with a
one-box stand-in is telling you something."* This is that, automated, because doing it by hand
over 154 files produces a list nobody can reproduce.

## What it does to a file

A candidate with **exactly one** `func …() -> Unit:` builds its fixture in one place. The body of
that function is replaced with `return RealUnit.build(self, <cell>)` — the Pass A1 helper — the
file is run, and the file is then restored from the backup **whatever happens**, including on a
crash or an interrupt. Nothing here is a fix; it is a probe, and it leaves no trace.

`<cell>` is the helper's own `cell` parameter when it has one and `Vector2i.ZERO` when it does
not. Every other parameter is dropped, and that is the instrument's main limitation: a helper
that takes `hp` or a weapon id was parameterising the fixture, and the substitution throws that
away along with the stand-in.

## Reading the output, and the trap in it

**A red file is not a `DRIFTED` row.** Three things make a substituted file fail and only the
first is a finding:

1. **The test asserted something a real unit contradicts** — a body with one part, a free socket
   that a real shell fills, a weapon the real loadout does not carry. That is `DRIFTED`.
2. **The substitution dropped a parameter the test needed.** An instrument artefact.
3. **The scenario changed underneath the test** — the real chaingunner costs different AP and
   does different damage than the stand-in pistol, so a balance assertion moves. Also an
   artefact, and the commonest of the three.

So this script **classifies nothing**. It emits `baseline` and `substituted` verdicts plus the
failure lines, and the reading is Pass B's work. A script that printed a verdict here would be
manufacturing exactly the confident-but-wrong list this taskblock exists to find.
"""
import argparse
import re
import subprocess
import sys
import json
import os

HELPER = re.compile(r"^func\s+(\w+)\s*\(([^)]*)\)\s*->\s*Unit\s*:\s*$", re.M)

# **The probe must not probe its own instrument.** `test_real_unit.gd`'s single `-> Unit` helper
# IS the deliberate one-box stand-in `RealUnit.check` exists to refuse, so substituting a real
# chaingunner into it makes the guard assert that a real unit is degenerate. It goes red for a
# reason that is the opposite of a finding, and the first run reported it alongside the real ones.
EXCLUDED = {"test/unit/logic/test_real_unit.gd"}
RUN = [
    "godot",
    "--headless",
    "-d",
    "--display-driver",
    "headless",
    "--audio-driver",
    "Dummy",
    "--path",
    ".",
    "-s",
    "res://tools/run_suite.gd",
    "--",
]


def substitute(source):
    """Source with the single `-> Unit` helper's body replaced, or None if not applicable."""
    matches = list(HELPER.finditer(source))
    if len(matches) != 1:
        return None
    match = matches[0]
    params = match.group(2)
    cell = "cell" if re.search(r"\bcell\s*:", params) else "Vector2i.ZERO"

    lines = source.split("\n")
    # **The signature's LAST line, not its first.** `[^)]*` spans newlines, so a helper whose
    # parameters are wrapped over several lines matches correctly and then had its own signature
    # overwritten from line two onward, leaving an orphaned `) -> Unit:` — three of the ninety-five
    # targets are wrapped, and all three came back as a parse error rather than as a result.
    start = source[: match.end()].count("\n")
    end = start + 1
    while end < len(lines) and (lines[end].strip() == "" or lines[end].startswith(("\t", " "))):
        end += 1
    # **The library is loaded here if the file never loads it**, because 26 of the 44 probe
    # targets do not — their fixtures never needed data. Without this the probe would report
    # three quarters of its runs red for "preset missing", which says nothing about the fixture
    # and would drown the failures that do.
    body = [
        "\tif DataLibrary.get_preset(RealUnit.PRESET_ID) == null:",
        "\t\tDataLibrary.load_all()",
        "\treturn RealUnit.build(self, %s)" % cell,
    ]
    return "\n".join(lines[: start + 1] + body + lines[end:])


# A substituted file can raise where the original never did, and `-d` answers a runtime error
# with an interactive debugger prompt. `run_tests.sh` documents the consequence: a break in the
# LAST script sits at `debug>` waiting for input that never comes. Closing stdin makes the prompt
# read EOF, and the timeout is the backstop — the slowest file in the suite is under 70 s.
TIMEOUT_S = 300


def run(path):
    """(passed, [failure lines]) for one test file."""
    env = dict(os.environ, GODOT_DISABLE_LEAK_CHECKS="1")
    try:
        proc = subprocess.run(
            RUN + ["--test=res://%s" % path],
            capture_output=True,
            text=True,
            env=env,
            stdin=subprocess.DEVNULL,
            timeout=TIMEOUT_S,
        )
    except subprocess.TimeoutExpired:
        return "timed-out", ["no summary within %d s" % TIMEOUT_S]
    out = proc.stdout + proc.stderr
    # The runner's own summary line is the only trustworthy verdict: a non-zero exit also
    # covers a debugger break, which is a different fact and is reported as `did-not-finish`.
    cost = re.search(r"(\d+) script\(s\), (\d+) test\(s\), (\d+) failure\(s\)", out)
    if not cost:
        return "did-not-finish", [l.strip() for l in out.split("\n") if "SCRIPT ERROR" in l][:6]
    fails = [l.strip() for l in out.split("\n") if "[Failed]" in l]
    return ("pass" if int(cost.group(3)) == 0 else "fail"), fails[:6]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("list", nargs="?", help="file with one test path per line")
    ap.add_argument("--files", nargs="*", default=[])
    ap.add_argument("--out", default="audit/substitution_probe.jsonl")
    args = ap.parse_args()

    paths = list(args.files)
    if args.list:
        paths += [l.strip() for l in open(args.list) if l.strip()]

    with open(args.out, "w") as sink:
        for i, path in enumerate(paths, 1):
            if path in EXCLUDED:
                sink.write(json.dumps({"file": path, "skipped": "the probe's own instrument"}) + "\n")
                print(f"[{i}/{len(paths)}] SKIP {path}", flush=True)
                continue
            source = open(path).read()
            swapped = substitute(source)
            if swapped is None:
                record = {"file": path, "skipped": "not exactly one `-> Unit` helper"}
                print(f"[{i}/{len(paths)}] SKIP {path}", flush=True)
                sink.write(json.dumps(record) + "\n")
                continue

            base_verdict, base_fails = run(path)
            try:
                open(path, "w").write(swapped)
                sub_verdict, sub_fails = run(path)
            finally:
                # Restored on every path out, including Ctrl-C. A probe that can leave a
                # rewritten test behind is a probe that edits the repo.
                open(path, "w").write(source)

            record = {
                "file": path,
                "baseline": base_verdict,
                "baseline_failures": base_fails,
                "substituted": sub_verdict,
                "substituted_failures": sub_fails,
            }
            sink.write(json.dumps(record) + "\n")
            sink.flush()
            print(f"[{i}/{len(paths)}] {base_verdict} -> {sub_verdict}  {path}", flush=True)
    print("wrote %s" % args.out)


if __name__ == "__main__":
    sys.exit(main())
