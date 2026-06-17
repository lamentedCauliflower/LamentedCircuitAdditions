# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) and other agents when working with code in this repository.

A Factorio 2.0 mod adding new circuit-network modes to the vanilla constant and selector combinators, presented through fully-replaced GUIs as native-feeling Modes.

## Commands

- **Tests**: `busted` (run from repo root; `.busted` resolves `domain/` modules). Must run on **Lua 5.2** — the version Factorio embeds, so test behaviour matches in-game.
- **Single test**: `busted spec/domain/stack_pack_spec.lua`, or filter by name `busted --filter "crafting time"`.
- **devenv** (Nix): `devenv shell` drops into Lua 5.2 + busted + stylua; `devenv test` runs the suite.
- **Format**: `stylua .`
- **Benchmark** (headless, measures per-tick Mode cost vs vanilla): `python bench/bench.py` — see `bench/README.md`. Requires a Factorio install; configures Modes via the remote interface since the GUI can't run headless.

## Branching & releases

Work on `dev`, merge to `main` to release. `main` is auto-versioned/changelogged/published to the Mod Portal by semantic-release from **conventional commits** (`feat`, `fix`, `perf`, `gui`, `locale`, etc.). Commit type drives the release — get it right.

## Architecture

**Two-layer split — keep it.** `domain/` is pure Lua decision logic with **no Factorio API access**; it is the only code with automated tests. `runtime/` + `control.lua` are the thin adapter layer that pulls data off game objects, calls domain modules, and writes results back. GUI and event wiring are verified manually in-game, not by tests. New logic goes in `domain/` behind a pure function; new game-object plumbing goes in `runtime/`.

**`control.lua`** is the only event-registration point. Both GUIs (`cc_gui`, `sc_gui`) subscribe to the *same* `on_gui_*` events and self-route by their `tags.lca` namespace — `fan_out` calls both handlers. `on_gui_opened` dispatches by entity type (constant- vs selector-combinator).

**Data stage (`data.lua`) adds nothing craftable** — only hidden, indestructible helper entities cloned from the vanilla combinators (`lca-hidden-output`, `-sentinel`, `-merge`, `-map`, `-gate`, `-anchor`). Script Modes build engine chains from these helpers so computation survives unpowered grids (`void_energy`).

**Modes are the core abstraction** (see `CONTEXT.md` for the precise domain language — read it before touching Mode semantics). Exactly one Mode is active per combinator; the first Mode reproduces vanilla behaviour ("Logistic Groups" / "Vanilla").
- Constant-combinator Modes live in `runtime/preset.lua` (runtime-generated recipe Presets from a Target Machine + Filters).
- Selector-combinator Modes live in `runtime/selector_mode.lua`: `crafting-time`, `memory-cell`, `recipe-products`, `recipe-finder`, `stack-pack` (constants at `selector_mode.MODE_*`), each backed by a pure module in `domain/`.

**Recompute loop**: state is keyed by `unit_number` in `storage.{cc,sc}_modes`. `selector_mode.dirty(unit_number)` marks a combinator for recompute; `on_tick` processes Lua Modes (Crafting-Time instead rewrites its hidden engine map directly). Modes that depend on research (`recipe-finder`, Presets) dirty on `on_research_finished`/`reversed`.

**Output is written as logistic-section filters.** A signal filter pairs a `value` (`{type,name,quality,comparator?}`) with `min`. **A request (`min ≠ 0`) needs a concrete `quality` on every value** — a quality-less filter is the "non-trivial item filter condition" the engine refuses to pair with a non-zero request, and this applies to *all* signal types (virtual, fluid, recipe…), not just items. Always set `quality = signal.quality or "normal"` (plus `comparator = "="`); the engine stores `"normal"` for symbols with no quality axis (verified headless on 2.0.x — see `cc_gui.elem_to_filter_value` and `selector_mode.write_output`). `comparator` must be `"="` if present; an inequality is itself non-trivial and is rejected.

**Persistence (`runtime/persist.lua`)** carries Mode state across blueprints, revival, paste, clone, undo/redo, and mining — wired in `control.lua` with entity filters that include the hidden helpers.

**Remote interface** `lamented-circuit-additions` → `configure_selector(entity, config)` drives Modes without the GUI (used by `bench/` and headless tooling).

## Agent skills

- **Issue tracker**: GitHub Issues (`lamentedCauliflower/LamentedCircuitAdditions`) via `gh`. See `docs/agents/issue-tracker.md`.
- **Triage labels**: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.
- **Domain docs**: `CONTEXT.md` (language) + `docs/adr/` (decisions). See `docs/agents/domain.md`.
