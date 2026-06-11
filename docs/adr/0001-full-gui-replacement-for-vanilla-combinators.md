# 0001 — Full GUI replacement for vanilla combinators

## Status

Accepted (2026-06-11)

## Context

The mod adds new behaviors to the vanilla constant combinator (presets) and selector
combinator (crafting-time mode, memory-cell mode). Factorio's engine hardcodes vanilla
entity GUIs: mods cannot insert options into the selector combinator's operation
dropdown or add controls inside the constant combinator's window.

Three approaches were considered:

1. **Relative panel** — keep the vanilla GUI, anchor a mod-owned side panel next to it.
2. **Full GUI replacement** — intercept `on_gui_opened`, suppress the vanilla GUI, and
   open a mod-built GUI that recreates the vanilla controls plus the new options in one
   unified dropdown.
3. **New entities** — ship separate combinator entities with custom GUIs.

## Decision

Full GUI replacement, for both the constant combinator and the selector combinator.
The mod GUI presents a single dropdown: vanilla behavior(s) plus the mod's modes, so
the player experiences the new modes as native options.

## Consequences

- Seamless UX: one dropdown per combinator, no bolted-on side panel, no new items.
- Existing combinators in existing saves gain the new functionality.
- The mod must reimplement and maintain the vanilla GUI surfaces it suppresses:
  the constant combinator's logistic-sections editor and all seven vanilla selector
  operation panels. This is the largest cost of the decision.
- Base-game GUI changes (new vanilla features, layout changes) require the mod to
  catch up manually; until then the replaced GUI lags vanilla.
- Other mods that also touch these entities' GUIs may conflict.
