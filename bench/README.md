# Combinator benchmark procedure

Measures the per-tick cost of each LCA selector-combinator Mode and compares
it to the vanilla selector combinator ("select max"), using Factorio's
built-in `--benchmark` on deterministic generated saves.

## How it works

`bench.py` runs one **variant** at a time:

| variant            | DUT per pair                                        |
| ------------------ | --------------------------------------------------- |
| `none`             | no DUT — baseline world (feeders, power, wiring)    |
| `vanilla`          | vanilla selector, `select max`                      |
| `crafting-time`    | LCA Crafting-Time Mode (assembling-machine-2)       |
| `memory-cell-hot`  | LCA Memory Cell, Update Condition holds every tick  |
| `memory-cell-idle` | LCA Memory Cell, Update Condition never holds       |
| `recipe-products`  | LCA Recipe Products Mode                            |
| `recipe-finder`    | LCA Recipe Finder Mode (items in, recipes out)      |

For each variant the script:

1. Generates a temp `lca-bench` mod from `mod-template/` with the variant,
   pair count, and signal count substituted in. Its `on_init` builds the
   world — `COUNT` pairs of constant-combinator feeder (`SIGNALS` signals,
   value 1) red-wired to the DUT, on a powered substation grid — and `on_init`
   runs at `--create` time, so the world is baked into the save.
2. Creates the save (`--create`, fixed seed, no enemies) with the repo
   symlinked in as the live mod.
3. Runs `--benchmark save.zip --benchmark-ticks N --benchmark-runs R` and
   takes the best run's ms/tick.

Cost attribution: `µs/DUT/tick = (variant − none) × 1000 / COUNT`. The LCA
numbers honestly include the whole architecture cost — script time, the
hidden output constant combinator, and the parked vanilla selector.

LCA Modes are configured headless through the
`remote.call("lamented-circuit-additions", "configure_selector", entity, config)`
interface (the GUI can't run headless).

## Running

```sh
bench/bench.py                                   # all variants, defaults
bench/bench.py --count 1000 --ticks 7200         # bigger world, longer run
bench/bench.py --variants vanilla crafting-time  # subset ("none" auto-added)
bench/bench.py --dynamic                         # input frame changes every tick
bench/bench.py --verify                          # 10-tick correctness check
```

Defaults: 500 pairs, 20 signals each, 3600 ticks × 3 runs. Binary defaults to
the Steam install; override with `--factorio` or `FACTORIO_BIN`. Everything
writes to an isolated `/tmp/lca-bench/` config/write dir, so it works while a
normal game is running.

`--dynamic` adds a per-pair "random signal" selector (interval 1) onto each
DUT input network, so the input frame changes every tick — the worst case for
the change-detection gating in `runtime/selector_mode.lua`.

`--verify` runs 10 ticks and prints in-game log checks instead of timings:
DUT status, input/output signal counts, and the first output signals. Use it
after harness or mod changes to confirm the benchmark measures real work.

## Interpreting

- Vanilla 2.0 combinators are event-driven C++: with static inputs they cost
  ~nothing, and even with `--dynamic` a selector measures ~0.08 µs/DUT/tick.
  A Lua mod cannot reach that — one Lua→C API call alone costs ~0.4 µs — so
  the `vs vanilla` ratio is only meaningful on `--dynamic` runs, and the
  practical targets are absolute: ~2–4 µs/DUT/tick static (sentinel-gated
  steady state), ~20–35 µs on ticks where the input actually changed.
- Key API costs measured on 2.0.76 (20-signal frames): `get_signals` ~20 µs,
  `network.signals` ~35 µs, `get_signal`/`get_signal_last_tick` ~0.4 µs,
  `entity.valid` ~0.1 µs. This is why the driver gates on a hidden sentinel
  arithmetic combinator (one scalar read per tick) instead of reading the
  frame every tick.
- `memory-cell-hot` and `--dynamic` runs are worst cases: every tick the
  input changes, so gating never skips work.
- Benchmark noise: single-digit percent between runs (worse while a desktop
  game is running); the script takes the best of `--runs`. Increase
  `--ticks`/`--runs` for final numbers.
