"""Turn compiler errors in build.log into GitHub annotations.

GitHub keeps at most 10 annotations of each level per step, so this emits a
slice of 30 errors per call (as error, warning and notice) starting at argv[1].
"""
import os
import re
import sys

start = int(sys.argv[1])
root = os.environ.get("GITHUB_WORKSPACE", "") + "/"
pattern = re.compile(r"^(/\S+?):(\d+):(\d+): error: (.*)$")

seen, errors = set(), []
for line in open("build.log", errors="replace"):
    m = pattern.match(line.strip())
    if m and m.groups() not in seen:
        seen.add(m.groups())
        errors.append(m.groups())

if start == 0:
    print(f"{len(errors)} unique compiler errors")
    if not errors:
        # Not a compile error (scheme, destination, signing...): surface the raw lines.
        other = [l.strip() for l in open("build.log", errors="replace") if "error" in l.lower()]
        for l in list(dict.fromkeys(other))[:10]:
            print(f"::error::{l[:500]}")
        if not other:
            for l in open("build.log", errors="replace").read().splitlines()[-10:]:
                print(f"::error::{l[:500]}")
for i, (path, line, col, msg) in enumerate(errors[start:start + 30]):
    level = ("error", "warning", "notice")[i // 10]
    print(f"::{level} file={path.replace(root, '')},line={line},col={col}::{msg}")
