# 0002 — Recipe Finder emits one Primary Recipe, not all producers

## Status

Accepted (2026-06-11)

## Context

Recipe Finder Mode maps an item or fluid signal to a recipe that produces it on
the Target Machine. Many items have several producers (solid fuel ×3, petroleum
gas via three oil-processing variants), so the mapping is not one-to-one.

Two approaches were considered:

1. **Emit all matching recipes** — no tie-break policy to maintain; downstream
   circuits decide.
2. **Emit one Primary Recipe** — a deterministic tie-break chain picks a single
   recipe per input signal.

## Decision

Emit exactly one Primary Recipe per input, chosen by the chain: recipe named
exactly like the item/fluid → recipe whose main product it is → alphabetically
first qualifying producer. Filters (Researched-only, No-fluid-inputs) and the
Target Machine's crafting categories bound the candidate set.

## Consequences

- The output is directly usable as-is — e.g. wired into a machine's
  set-recipe circuit input — without downstream disambiguation logic.
- Input values pass through cleanly; an all-matches output would have had no
  obvious value semantics per recipe.
- The tie-break chain is policy the mod must own and document. Modded recipe
  sets with odd names/main products may pick a recipe the player did not
  expect, and changing the chain later changes behavior in existing saves.
- Players who genuinely want the full producer set have no Mode for it; that
  would be a separate Mode if ever needed.
