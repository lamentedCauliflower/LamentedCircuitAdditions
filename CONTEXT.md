# Lamented Circuit Additions

A Factorio 2.0 mod that adds new circuit-network behaviors to the vanilla constant
combinator and selector combinator, presented through replaced GUIs as native-feeling
modes.

## Language

**Mode**:
The behavior a combinator is set to via the mod's dropdown. Exactly one Mode is active
per combinator; the first Mode always reproduces unmodded behavior — named
"Logistic Groups" on the constant combinator (whose 2.0 output is configured through
logistic groups) and "Vanilla" on the selector combinator.
_Avoid_: function, setting, operation (reserved for vanilla selector operations)

**Preset**:
A constant combinator Mode that generates its output signals at runtime from game
prototypes, parametrized by a Target Machine and Filters. Not a static signal list.
_Avoid_: template, profile

**Craftable Set**:
The recipes a Target Machine can craft: recipe category is among the machine's
crafting categories, after Filters are applied. Emitted as the recipe's main item
product signal (value 1) when it has one, falling back to the recipe signal
otherwise; recipes sharing a product collapse into one signal.
_Avoid_: recipe list, item list

**Target Machine**:
The crafting-machine entity a Preset or selector Mode is computed against, chosen via
an entity picker in the GUI. Determines crafting categories and crafting speed.
_Avoid_: assembler (that's just the MVP default), building

**Filter**:
A per-combinator toggle narrowing the Craftable Set. Two exist: Researched-only
(default on, auto-recomputes on research changes) and No-fluid-inputs (default off).
_Avoid_: option, flag

**Crafting-Time Mode**:
A selector combinator Mode that maps each input recipe signal to the same recipe
signal valued at its crafting time in ticks on the Target Machine
(floor(recipe energy / crafting speed × 60)). Non-recipe inputs are dropped; input
values are ignored (any nonzero value is a presence flag).
_Avoid_: recipe time, duration mode

**Memory Cell**:
A selector combinator Mode that holds a Stored Frame and outputs it continuously.
Level-triggered: every tick the Update Condition holds, the Stored Frame is replaced
by the full combined input; storing an empty input clears the cell.
_Avoid_: latch, register

**Update Condition**:
A standard circuit condition (signal ▸ comparator ▸ signal-or-constant) evaluated
against the Memory Cell's combined red+green input each tick.
_Avoid_: write enable, trigger

**Stored Frame**:
The complete set of signals (red+green summed) a Memory Cell captured last time its
Update Condition held.
_Avoid_: snapshot, state
