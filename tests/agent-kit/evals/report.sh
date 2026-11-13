#!/usr/bin/env bash
# Turn one or more results.jsonl directories into a markdown report on stdout.
#   bash tests/agent-kit/evals/report.sh DIR [DIR...]
# Exit 0; exit 2 when no results.jsonl is found under any given directory.
set -u

if [ $# -eq 0 ]; then
  echo "usage: report.sh DIR [DIR...]" >&2
  exit 2
fi

PYTHONDONTWRITEBYTECODE=1 PYTHONIOENCODING=utf-8 python3 -B - "$@" <<'PY'
import json
import os
import sys

dirs = sys.argv[1:]
rows = []
files = 0
for d in dirs:
    found = []
    if os.path.isdir(d):
        for root, subdirs, names in os.walk(d):
            subdirs.sort()
            if "results.jsonl" in names:
                found.append(os.path.join(root, "results.jsonl"))
    for path in sorted(found):
        files += 1
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except ValueError:
                    continue
                if isinstance(obj, dict) and "task" in obj and "label" in obj:
                    rows.append(obj)

if files == 0:
    sys.stderr.write("report.sh: no results.jsonl found under: %s\n" % ", ".join(dirs))
    sys.exit(2)

labels = []
for r in rows:
    if r["label"] not in labels:
        labels.append(r["label"])
tasks = sorted({r["task"] for r in rows})


def num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def group(label, task=None):
    return [r for r in rows if r["label"] == label and (task is None or r["task"] == task)]


def cell(rs):
    if not rs:
        return ["-", "-", "-"]
    k = sum(1 for r in rs if r.get("pass") is True)
    costs = [r["cost_usd"] for r in rs if num(r.get("cost_usd"))]
    durs = [r["duration_s"] for r in rs if num(r.get("duration_s"))]
    cost = "%.2f" % (sum(costs) / len(costs)) if costs else "n/a"
    dur = "%.1f" % (sum(durs) / len(durs)) if durs else "n/a"
    return ["%d/%d" % (k, len(rs)), cost, dur]


print("# Eval report: " + ", ".join(dirs))
print()
head = ["Task"]
for l in labels:
    head += ["%s pass" % l, "%s cost_usd" % l, "%s duration_s" % l]
print("| " + " | ".join(head) + " |")
print("|" + "|".join(["---"] * len(head)) + "|")
for t in tasks:
    cells = [t]
    for l in labels:
        cells += cell(group(l, t))
    print("| " + " | ".join(cells) + " |")
tot = ["Total"]
for l in labels:
    tot += cell(group(l))
print("| " + " | ".join(tot) + " |")
print()

if len(labels) >= 2:
    first = labels[0]

    def rate(l, t):
        rs = group(l, t)
        if not rs:
            return None
        return sum(1 for r in rs if r.get("pass") is True) / float(len(rs))

    for l in labels[1:]:
        w = lo = ti = 0
        for t in tasks:
            a, b = rate(l, t), rate(first, t)
            if a is None or b is None:
                continue
            if a > b:
                w += 1
            elif a < b:
                lo += 1
            else:
                ti += 1
        print("vs %s: %s wins %d, losses %d, ties %d" % (first, l, w, lo, ti))
    print()

for l in labels:
    kit = [r for r in group(l) if r.get("arm") == "kit"]
    n = sum(1 for r in kit if r.get("spawns") == 0 and not isinstance(r.get("spawns"), bool))
    if n:
        print("warning: %d kit run(s) with spawns 0 (the kit may not have run)" % n)
for l in labels:
    n = 0
    for r in group(l):
        sr = r.get("stop_reason")
        if r.get("timed_out") is True or (isinstance(sr, str) and sr.startswith("error_max")):
            n += 1
    if n:
        print("note: %d run(s) of %s stopped by budget or timeout" % (n, l))
print()
print("caveat: at 10 tasks × 3 runs, differences below roughly 25 percentage points are within noise "
      "(K3: even a 24-task, three-run design hides differences under about 10 points); "
      "there are no pass/fail thresholds")
PY
