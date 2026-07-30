#!/usr/bin/env python3
"""Read/write the audit CSV's judgement columns.

taskblock-49 Pass B. The point is that the VOCABULARY lives in the CSV, not in
anyone's head: `list` prints every distinct rule string already used, so the sweep
can be resumed after any interruption and keep reusing strings instead of inventing
near-duplicates. A near-duplicate is how a cluster hides, which is the one way this
column can be filled in completely and still be worthless.
"""
import csv, sys, collections

PATH = "test/suite_audit.csv"


def rows():
    with open(PATH, newline="") as f:
        return list(csv.DictReader(f))


def fieldnames():
    with open(PATH, newline="") as f:
        return csv.DictReader(f).fieldnames


def save(data, names):
    # `names` is passed in, never re-read here. Opening PATH for write truncates it, so
    # reading the header inside this function returned None from an empty file and
    # destroyed the CSV — restored from git. Read before you truncate.
    with open(PATH, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=names)
        w.writeheader()
        w.writerows(data)


def cmd_list():
    counts = collections.Counter(r["rule_guarded"] for r in rows() if r["rule_guarded"])
    for rule, n in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])):
        print(f"{n:4d}  {rule}")
    print(f"--- {len(counts)} distinct rules over {sum(counts.values())} classified rows")


def cmd_progress():
    data = rows()
    done = sum(1 for r in data if r["rule_guarded"])
    files = collections.Counter(r["origin_file"] for r in data if not r["rule_guarded"])
    print(f"{done}/{len(data)} rows classified")
    print(f"{len(files)} files with unclassified rows; next few:")
    for name, n in sorted(files.items())[:8]:
        print(f"   {n:4d}  {name}")


def cmd_show(pattern):
    for r in rows():
        if pattern in r["origin_file"]:
            print(f"{r['test_name']}\t{r['rule_guarded']}")


def cmd_set():
    """stdin: origin_file<TAB>test_name<TAB>rule[<TAB>description]"""
    updates = {}
    for line in sys.stdin:
        line = line.rstrip("\n")
        if not line.strip():
            continue
        parts = line.split("\t")
        key = (parts[0], parts[1])
        updates[key] = (parts[2], parts[3] if len(parts) > 3 else None)
    names = fieldnames()
    data = rows()
    hit = 0
    for r in data:
        key = (r["origin_file"], r["test_name"])
        if key in updates:
            rule, desc = updates[key]
            r["rule_guarded"] = rule
            if desc is not None:
                r["description"] = desc
            hit += 1
    if hit != len(updates):
        # A miss means a file/test name that does not exist — silently writing the rest
        # would leave the sweep looking complete with rows quietly unclassified.
        missing = [k for k in updates if not any(
            (r["origin_file"], r["test_name"]) == k for r in data)]
        print(f"ERROR: {len(missing)} requested rows not found, nothing written:")
        for m in missing[:10]:
            print(f"   {m[0]}  {m[1]}")
        sys.exit(1)
    save(data, names)
    print(f"set {hit} of {len(updates)} requested rows")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "progress"
    if cmd == "list":
        cmd_list()
    elif cmd == "progress":
        cmd_progress()
    elif cmd == "show":
        cmd_show(sys.argv[2])
    elif cmd == "set":
        cmd_set()
    else:
        print(__doc__)
