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
  the `vs vanilla` ratio is only meaningful on `--dynamic` runs.
- Two strategies, by Mode (measured 2.0.76, COUNT=500, 20-signal frames):
  - **Crafting-Time is fully engine-driven** (a hidden merge→map→gate combinator
    chain, zero per-tick Lua). It measures **~0.01 µs/DUT static, ~0.9 µs dynamic**
    — within noise of vanilla. Config changes rewrite the map constant combinator;
    steady and dynamic ticks are pure engine C++.
  - **Memory Cell, Recipe Products, Recipe Finder** keep a per-tick Lua driver but
    gate it through grouped hidden sentinels: **~0.58 µs/DUT static, ~7–10 µs
    dynamic** (Recipe Finder costliest). The dynamic figure is the engine-API floor
    (the ~20 µs bulk `get_signals` only runs on actual input-change ticks).
- The static path for the Lua Modes used to be dominated by a per-DUT scalar
  sentinel read. Caching the *bound* `get_signal_last_tick` (skipping the LuaObject
  `__index` lookup) cut that ~3.5 → ~1 µs; **grouping** up to 32 same-surface
  sentinels under one hidden anchor (one scalar read per group, skipping the whole
  group when its summed signal is unchanged) cut it further to ~0.58 µs. What
  remains is the engine cost of the per-DUT hidden helper combinators, not Lua.
- Key API costs measured on 2.0.76 (20-signal frames): `get_signals` ~20 µs,
  `network.signals` ~35 µs, `get_signal`/`get_signal_last_tick` ~0.4 µs (plus a
  comparable LuaObject `__index` cost per uncached method access),
  `entity.valid` ~0.1 µs.
- `memory-cell-hot` and `--dynamic` runs are worst cases for the Lua Modes: every
  tick the input changes, so gating never skips the bulk read.
- Benchmark noise: single-digit percent between runs (worse while a desktop
  game is running); the script takes the best of `--runs`. Increase
  `--ticks`/`--runs` for final numbers.
