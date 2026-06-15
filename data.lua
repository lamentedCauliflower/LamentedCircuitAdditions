-- Data stage: hidden helper entities only; the mod adds nothing craftable.
local util = require("util")

local HIDDEN_FLAGS = {
  "placeable-off-grid",
  "not-on-map",
  "not-blueprintable",
  "not-deconstructable",
  "hide-alt-info",
  "not-upgradable",
  "no-copy-paste",
  "not-selectable-in-game",
}

-- Clone a combinator prototype into an invisible, indestructible helper.
-- `void_energy` keeps the helper working on unpowered grids (the script
-- Modes must compute regardless of the host selector's power).
local function hidden_clone(source_type, source_name, new_name, void_energy)
  local proto = util.table.deepcopy(data.raw[source_type][source_name])
  proto.name = new_name
  proto.hidden = true
  proto.flags = HIDDEN_FLAGS
  proto.minable = nil
  proto.selectable_in_game = false
  proto.selection_box = nil
  proto.collision_box = { { 0, 0 }, { 0, 0 } }
  proto.collision_mask = { layers = {} }
  proto.sprites = util.empty_sprite()
  proto.activity_led_sprites = util.empty_sprite()
  proto.draw_circuit_wires = false
  proto.created_smoke = nil
  if void_energy then
    proto.energy_source = { type = "void" }
  end
  return proto
end

-- Invisible constant combinator that carries script-computed output signals
-- for the selector combinator's script-driven Modes. Wired to the selector's
-- output connectors at runtime with script-origin wires.
local output = hidden_clone("constant-combinator", "constant-combinator", "lca-hidden-output")

-- Invisible arithmetic combinator that watches a script-Mode selector's
-- input networks and folds them into one sentinel signal (each XOR K -> S).
-- The engine recomputes it event-driven, so the per-tick driver can detect
-- input changes with a single scalar read instead of copying every signal.
local sentinel = hidden_clone("arithmetic-combinator", "arithmetic-combinator", "lca-hidden-sentinel", true)

-- Invisible arithmetic combinator that sums the sentinel outputs of a group
-- of script-Mode selectors onto one signal (S + 0 -> S). The driver reads
-- this one scalar per group; an unchanged sum lets it skip the whole group.
local anchor = hidden_clone("arithmetic-combinator", "arithmetic-combinator", "lca-hidden-anchor", true)

-- Crafting-Time engine chain (no per-tick Lua). merge collapses the host's
-- red+green inputs onto one wire (each + 0 -> each); map is a constant
-- combinator holding every recipe -> crafting-tick count for the Target
-- Machine; gate is a decider that, for each recipe present on the merged
-- input, emits it with the count copied from map.
local merge = hidden_clone("arithmetic-combinator", "arithmetic-combinator", "lca-hidden-merge", true)
local map = hidden_clone("constant-combinator", "constant-combinator", "lca-hidden-map")
local gate = hidden_clone("decider-combinator", "decider-combinator", "lca-hidden-gate", true)

data:extend{ output, sentinel, anchor, merge, map, gate }
