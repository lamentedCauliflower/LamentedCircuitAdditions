#!/usr/bin/env python3
"""Benchmark LCA selector-combinator Modes against the vanilla selector.

For each variant this script generates a temp "lca-bench" mod (from
bench/mod-template/) that builds a deterministic combinator world at map
creation, creates a save, and runs Factorio's --benchmark on it. The "none"
variant builds the same world without the DUT combinators, so
(variant - none) isolates the per-combinator cost.

Usage:
  bench/bench.py                 # all variants, defaults
  bench/bench.py --variants vanilla crafting-time --count 1000
  bench/bench.py --dynamic       # input frame changes every tick
  bench/bench.py --verify        # 10-tick run, print the in-game checks

Requires the Factorio binary (default: the Steam install). Uses an isolated
config/write dir under /tmp/lca-bench so it works while the game is running.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_BIN = os.path.expanduser(
    "~/.steam/steam/steamapps/common/Factorio/bin/x64/factorio"
)
WORK = "/tmp/lca-bench"
VARIANTS = [
    "none",
    "vanilla",
    "crafting-time",
    "memory-cell-hot",
    "memory-cell-idle",
    "recipe-products",
    "recipe-finder",
]


def write_config(factorio_bin):
    data_dir = os.path.normpath(
        os.path.join(os.path.dirname(factorio_bin), "..", "..", "data")
    )
    write_dir = os.path.join(WORK, "write")
    os.makedirs(write_dir, exist_ok=True)
    config = os.path.join(WORK, "config.ini")
    with open(config, "w") as f:
        f.write(f"[path]\nread-data={data_dir}\nwrite-data={write_dir}\n")
    return config


def make_mods_dir(variant, args):
    mods = os.path.join(WORK, variant, "mods")
    shutil.rmtree(mods, ignore_errors=True)
    os.makedirs(mods)
    os.symlink(REPO, os.path.join(mods, "lamented-circuit-additions"))

    bench_mod = os.path.join(mods, "lca-bench")
    os.makedirs(bench_mod)
    template_dir = os.path.join(REPO, "bench", "mod-template")
    shutil.copy(
        os.path.join(template_dir, "info.json"), os.path.join(bench_mod, "info.json")
    )
    with open(os.path.join(template_dir, "control.lua")) as f:
        control = f.read()
    control = (
        control.replace("__VARIANT__", variant)
        .replace("__COUNT__", str(args.count))
        .replace("__SIGNALS__", str(args.signals))
        .replace("__DYNAMIC__", "true" if args.dynamic else "false")
        .replace("__VERIFY__", "true" if args.verify else "false")
    )
    with open(os.path.join(bench_mod, "control.lua"), "w") as f:
        f.write(control)

    with open(os.path.join(mods, "mod-list.json"), "w") as f:
        json.dump(
            {
                "mods": [
                    {"name": "base", "enabled": True},
                    {"name": "lamented-circuit-additions", "enabled": True},
                    {"name": "lca-bench", "enabled": True},
                ]
            },
            f,
        )
    return mods


def run_factorio(factorio_bin, config, mods, cli_args):
    cmd = [factorio_bin, "-c", config, "--mod-directory", mods] + cli_args
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
    return result


def bench_variant(variant, args, factorio_bin, config):
    mods = make_mods_dir(variant, args)
    save = os.path.join(WORK, variant, "save.zip")
    if os.path.exists(save):
        os.remove(save)

    result = run_factorio(
        factorio_bin,
        config,
        mods,
        [
            "--create",
            save,
            "--map-gen-settings",
            os.path.join(REPO, "bench", "map-gen-settings.json"),
        ],
    )
    if not os.path.exists(save):
        print(f"[{variant}] save creation FAILED:", file=sys.stderr)
        print(result.stdout[-3000:], file=sys.stderr)
        print(result.stderr[-3000:], file=sys.stderr)
        sys.exit(1)

    ticks = 10 if args.verify else args.ticks
    runs = 1 if args.verify else args.runs
    result = run_factorio(
        factorio_bin,
        config,
        mods,
        [
            "--benchmark",
            save,
            "--benchmark-ticks",
            str(ticks),
            "--benchmark-runs",
            str(runs),
            "--disable-audio",
        ],
    )

    if args.verify:
        log_path = os.path.join(WORK, "write", "factorio-current.log")
        lines = []
        for source in [result.stdout, open(log_path).read() if os.path.exists(log_path) else ""]:
            lines += [l for l in source.splitlines() if "LCA-BENCH" in l or "rror" in l]
        print(f"[{variant}]")
        for line in lines:
            print("   ", line.strip())
        return None

    # "Performed 3600 updates in 1234.567 ms"
    per_tick = [
        float(ms) / float(updates)
        for updates, ms in re.findall(
            r"Performed (\d+) updates in (\d+\.\d+) ms", result.stdout
        )
    ]
    if not per_tick:
        print(f"[{variant}] benchmark FAILED:", file=sys.stderr)
        print(result.stdout[-3000:], file=sys.stderr)
        print(result.stderr[-3000:], file=sys.stderr)
        sys.exit(1)
    best = min(per_tick)
    print(f"[{variant}] best {best:.4f} ms/tick over {len(per_tick)} run(s)")
    return best


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--factorio", default=os.environ.get("FACTORIO_BIN", DEFAULT_BIN))
    parser.add_argument("--variants", nargs="+", default=VARIANTS, choices=VARIANTS)
    parser.add_argument("--count", type=int, default=500, help="DUT combinators")
    parser.add_argument("--signals", type=int, default=20, help="signals per feeder")
    parser.add_argument("--ticks", type=int, default=3600)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--dynamic", action="store_true", help="change the input frame every tick")
    parser.add_argument("--verify", action="store_true", help="10-tick correctness check, no timing")
    args = parser.parse_args()

    variants = list(args.variants)
    if "none" not in variants and not args.verify:
        variants.insert(0, "none")

    config = write_config(args.factorio)
    results = {}
    for variant in variants:
        results[variant] = bench_variant(variant, args, args.factorio, config)

    if args.verify:
        return

    baseline = results.get("none", 0.0)
    vanilla_us = None
    if results.get("vanilla") is not None:
        vanilla_us = (results["vanilla"] - baseline) * 1000.0 / args.count

    print()
    print(f"count={args.count} signals={args.signals} ticks={args.ticks} "
          f"runs={args.runs} dynamic={args.dynamic}")
    print(f"{'variant':<18} {'ms/tick':>9} {'Δ baseline':>11} {'µs/DUT/tick':>12} {'vs vanilla':>11}")
    for variant in variants:
        ms = results[variant]
        delta = ms - baseline
        per_dut = delta * 1000.0 / args.count
        ratio = ""
        if vanilla_us and variant not in ("none", "vanilla"):
            ratio = f"{per_dut / vanilla_us:10.1f}x"
        elif variant == "vanilla":
            ratio = f"{'1.0x':>11}"
        print(f"{variant:<18} {ms:9.4f} {delta:11.4f} {per_dut:12.3f} {ratio:>11}")


if __name__ == "__main__":
    main()
