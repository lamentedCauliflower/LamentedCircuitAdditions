-- Data stage: hidden helper entities only; the mod adds nothing craftable.
local util = require("util")

-- Invisible constant combinator that carries script-computed output signals
-- for the selector combinator's script-driven Modes. Wired to the selector's
-- output connectors at runtime with script-origin wires.
local hidden = util.table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
hidden.name = "lca-hidden-output"
hidden.hidden = true
hidden.flags = {
  "placeable-off-grid",
  "not-on-map",
  "not-blueprintable",
  "not-deconstructable",
  "hide-alt-info",
  "not-upgradable",
  "no-copy-paste",
  "not-selectable-in-game",
}
hidden.minable = nil
hidden.selectable_in_game = false
hidden.selection_box = nil
hidden.collision_box = { { 0, 0 }, { 0, 0 } }
hidden.collision_mask = { layers = {} }
hidden.sprites = util.empty_sprite()
hidden.activity_led_sprites = util.empty_sprite()
hidden.draw_circuit_wires = false
hidden.created_smoke = nil

-- Invisible arithmetic combinator that watches a script-Mode selector's
-- input networks and folds them into one sentinel signal (each XOR K -> S).
-- The engine recomputes it event-driven, so the per-tick driver can detect
-- input changes with a single scalar read instead of copying every signal.
-- Void energy: it must keep working on unpowered grids.
local sentinel = util.table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
sentinel.name = "lca-hidden-sentinel"
sentinel.hidden = true
sentinel.flags = {
  "placeable-off-grid",
  "not-on-map",
  "not-blueprintable",
  "not-deconstructable",
  "hide-alt-info",
  "not-upgradable",
  "no-copy-paste",
  "not-selectable-in-game",
}
sentinel.minable = nil
sentinel.selectable_in_game = false
sentinel.selection_box = nil
sentinel.collision_box = { { 0, 0 }, { 0, 0 } }
sentinel.collision_mask = { layers = {} }
sentinel.energy_source = { type = "void" }
sentinel.sprites = util.empty_sprite()
sentinel.activity_led_sprites = util.empty_sprite()
sentinel.draw_circuit_wires = false
sentinel.created_smoke = nil

data:extend{ hidden, sentinel }
