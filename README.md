[![Tests](https://github.com/lamentedCauliflower/LamentedCircuitAdditions/actions/workflows/test.yml/badge.svg)](https://github.com/lamentedCauliflower/LamentedCircuitAdditions/actions/workflows/test.yml)
[![Release](https://github.com/lamentedCauliflower/LamentedCircuitAdditions/actions/workflows/release.yml/badge.svg?branch=main)](https://github.com/lamentedCauliflower/LamentedCircuitAdditions/actions/workflows/release.yml)

# Lamented Circuit Additions

A Factorio 2.0 mod that adds new modes to the vanilla combinators:

- **Constant combinator**: runtime-generated presets — e.g. output every recipe a chosen
  machine can currently craft, kept up to date as research completes.
- **Selector combinator**: a crafting-time mode (recipe signal in, crafting time in ticks
  out) and a memory cell mode (hold a signal frame, update it when a condition is met).

Domain language lives in [`CONTEXT.md`](CONTEXT.md); architectural decisions in
[`docs/adr/`](docs/adr/).

## Development

The codebase is split in two:

- `domain/` — pure Lua decision logic, no Factorio API access.
- `control.lua` and future runtime modules — the thin layer that adapts game objects to
  the domain modules and back.

Only the pure domain modules are covered by automated tests; GUI and event wiring are
verified manually in-game.

### Running the tests

Tests use [busted](https://lunarmag.es/busted/) on Lua 5.2 (the Lua version Factorio
embeds):

```sh
luarocks install busted
busted
```

The same suite runs in CI on every push and pull request.

## Releasing

Releases are automated with [semantic-release](https://github.com/semantic-release/semantic-release)
and [semantic-release-factorio](https://github.com/fgardt/semantic-release-factorio):
pushes to `main` are analyzed (conventional commits), versioned, changelogged, packaged
via `git archive` (see [`.gitattributes`](.gitattributes) for excluded files), and
published to the [Factorio Mod Portal](https://mods.factorio.com). Work happens on `dev`
and merges into `main` to release.

Commit types that reach the changelog: `feat`/`feature`, `fix`, `perf`/`performance`,
`compat`/`compatibility`, `balance`, `graphics`, `sound`, `gui`, `info`, `locale`,
`translate`, `control`, `other`.
