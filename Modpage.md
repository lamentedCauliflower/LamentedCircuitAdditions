# Summary (plain text)

New circuit modes for the vanilla constant and selector combinators, added straight into their windows as native-feeling options — runtime recipe presets, crafting-time lookup, recipe products and reverse recipe lookup, a memory cell, and slot-based item packing. No new entities, works in existing saves.

---

# Description (Markdown)

**Lamented Circuit Additions** adds new behaviours to the combinators you already use. There are no new items to unlock and no extra entities to place — the mod replaces the vanilla constant and selector combinator windows with faithful recreations that add its modes to the same dropdown you already know. Pick a mode, and the combinator just does it.

Everything works in existing saves, survives blueprinting, copy-paste and undo, and is multiplayer-safe.

## Constant combinator

- **Logistic Groups** — the unmodded behaviour, untouched.
- **Craftable Set** — outputs every recipe a chosen machine can currently craft, as recipe signals. Pick a target machine; optionally restrict to researched recipes only or exclude recipes with fluid ingredients. The output keeps itself up to date as you complete research.

## Selector combinator

- **Vanilla** — all seven stock selector operations, reproduced exactly.
- **Crafting time** — maps each input recipe signal to its crafting time in ticks on a target machine. Fully engine-driven, so it costs nothing per tick.
- **Recipe products** — maps each input recipe signal to that recipe's products at their per-craft amounts. Shared products are summed; quality is carried through.
- **Recipe finder** — for each input item or fluid signal, outputs the recipe that produces it on a target machine, keeping the input value. The same researched-only and no-fluid filters as Craftable Set apply.
- **Memory cell** — holds a frame of signals and outputs it continuously. Every tick your update condition holds against the combined input, the stored frame is replaced; storing an empty input clears it. Supports the `Everything` / `Anything` / `Each` wildcards and a manual clear button.
- **Stack pack** — packs the input item signals into the first **X slots**, using each item's stack size, and outputs the amount that fits. Set X as a number or read it from a signal. Items are ordered by count exactly like the vanilla *Select input* operation (highest or lowest), so the biggest stockpiles claim slots first. Perfect for capping a loading order to a wagon, chest, or buffer of a known size. Non-item signals and the budget signal itself are never included in the output.

## Design

The mod is built around Factorio 2.0 paradigms (logistic groups, qualities, recipe signals) and leans on the engine wherever possible — hidden combinator chains do the work for free when they can, and the Lua-driven modes only recompute when their inputs or settings actually change.

Source and issue tracker: [GitHub](https://github.com/lamentedCauliflower/LamentedCircuitAdditions).

---

# FAQ (Markdown)

**Will this change my existing combinators?**
No. Existing combinators keep their current behaviour (the first dropdown option is always the unmodded one). The new modes are opt-in per combinator.

**Do I need to unlock or craft anything?**
No. There are no new items, recipes or entities. The modes appear in the normal combinator window.

**Is it multiplayer-safe?**
Yes. All modes are deterministic and run identically on every client.

**Do the new modes survive blueprints, copy-paste and undo?**
Yes. A combinator's mode and settings travel with blueprints, blueprint books, copy-paste, cloning and undo/redo. Vanilla-mode combinators carry no extra data.

**Does Stack Pack handle fluids?**
No. Slots are item slots, so only item signals are packed. Fluids, recipe signals and virtual signals on the same wire are ignored.

**In Stack Pack, what happens when the slot budget runs out partway through an item?**
That item outputs a partial amount — the part of it that fits in the remaining slots — so the budget is respected exactly rather than rounded to whole items. The partial stack fills first.

**If I read the Stack Pack budget X from a signal, does that signal get packed too?**
No. The signal you choose as the budget source is excluded from packing, so your control signal never eats a slot or leaks into the output.

**Why are the combinator windows slightly different from vanilla?**
Factorio hardcodes the vanilla combinator GUIs — a mod can't add options to them. To present the new modes as native dropdown entries, the mod recreates those windows. It tracks the vanilla layout, but base-game GUI changes may take a moment to catch up.

**Does it work with other mods?**
It works alongside most mods. Other mods that also replace these specific combinator windows can conflict, since only one replacement can win.

**Does it support quality?**
Yes. Quality is respected and carried through wherever it applies — recipe products and packed items keep their input quality, and same-item-different-quality signals are treated separately.
