#!/usr/bin/env python3
"""Compute critical path, wave structure, and parallelism ceiling for a plan DAG.

Input is a JSON file describing the plan's tasks:

    {
      "T1": {"dur": 12.5, "deps": []},
      "T3": {"dur": 6.5,  "deps": ["T1"]}
    }

`dur` is minutes. Use measured durations (from subagent telemetry) for a retrospective,
or planned estimates when reviewing a plan before execution.

Emits the metrics required by the proposed Throughput Summary thresholds:
critical path vs serial, largest packet share of critical path, wave widths,
and single-task waves.

Usage:
    python3 tools/critical-path.py tools/examples/baseline-dag.json
"""
import collections
import json
import sys


def load(path):
    raw = json.load(open(path))
    # Keys beginning with "_" are metadata (comments, provenance), not tasks.
    tasks = {k: v for k, v in raw.items() if not k.startswith("_")}
    dur = {k: v["dur"] for k, v in tasks.items()}
    deps = {k: v.get("deps", []) for k, v in tasks.items()}
    return dur, deps


def finish_times(dur, deps):
    fin = {}

    def end(t):
        if t in fin:
            return fin[t]
        start = max([end(d) for d in deps[t]] + [0])
        fin[t] = start + dur[t]
        return fin[t]

    for t in dur:
        end(t)
    return fin


def critical_chain(fin, deps):
    node = max(fin, key=fin.get)
    chain = []
    while True:
        chain.append(node)
        if not deps[node]:
            break
        node = max(deps[node], key=lambda d: fin[d])
    chain.reverse()
    return chain


def depth_levels(deps):
    lvl = {}

    def L(t):
        if t in lvl:
            return lvl[t]
        lvl[t] = 0 if not deps[t] else 1 + max(L(d) for d in deps[t])
        return lvl[t]

    for t in deps:
        L(t)
    return lvl


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    dur, deps = load(sys.argv[1])
    fin = finish_times(dur, deps)
    serial = sum(dur.values())
    cp = max(fin.values())
    chain = critical_chain(fin, deps)

    print(f"Serial total          : {serial:.0f} min")
    print(f"Critical path         : {cp:.0f} min")
    print(f"Max speedup ceiling   : {serial/cp:.2f}x  ({(1-cp/serial)*100:.0f}% cut)")
    print(f"Critical path ratio   : {cp/serial*100:.0f}% of serial   [threshold <= 60%]")
    print(f"Chain                 : {' -> '.join(chain)}")

    biggest = max(chain, key=lambda t: dur[t])
    share = dur[biggest] / cp * 100
    print(f"Largest packet on path: {biggest} = {dur[biggest]:.1f} min "
          f"({share:.0f}% of critical path)   [threshold <= 20%]")

    lvl = depth_levels(deps)
    waves = collections.defaultdict(list)
    for t in dur:
        waves[lvl[t]].append(t)

    print("\nWave structure (dependency depth):")
    singles = []
    for k in sorted(waves):
        members = sorted(waves[k], key=lambda x: (len(x), x))
        span = max(dur[t] for t in members)
        if len(members) == 1:
            singles.append(k)
        print(f"  wave {k}: width={len(members):>2}  span={span:>5.1f} min  {members}")
    total_wave = sum(max(dur[t] for t in waves[k]) for k in waves)
    print(f"\nSum of wave spans     : {total_wave:.0f} min")

    last_third = max(waves) - (max(waves) // 3)
    tail_singles = [w for w in singles if w >= last_third]
    print(f"Single-task waves     : {singles or 'none'}")
    print(f"  in final third      : {tail_singles or 'none'}   [threshold: none]")


if __name__ == "__main__":
    main()
