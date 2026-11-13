"""Hidden check: report outputs for fixed inputs match the recorded outputs."""
import json
import os
import sys

proj = os.environ["PROJ_DIR"]
sys.path.insert(0, proj)
data = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "expected.json")))

import report  # noqa: E402

bad = 0
for fn, per_case in sorted(data["expected"].items()):
    func = getattr(report, fn)
    for case, want in sorted(per_case.items()):
        rows = [tuple(r) for r in data["cases"][case]]
        got = func(rows)
        if got != want:
            bad += 1
            print("MISMATCH %s/%s" % (fn, case))
print("mismatches:", bad)
sys.exit(1 if bad else 0)
