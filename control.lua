-- Runtime entry point. Factorio API access lives here and in runtime/;
-- decision logic belongs in pure modules under domain/.
local cc_gui = require("runtime.cc_gui")
local sc_gui = require("runtime.sc_gui")
local preset = require("runtime.preset")
local selector_mode = require("runtime.selector_mode")
local persist = require("runtime.persist")

script.on_init(function()
  storage.cc_gui = {}
  storage.cc_modes = {}
  storage.sc_gui = {}
  storage.sc_modes = {}
end)

script.on_configuration_changed(function()
  -- Rebuild every script Mode's hidden helpers (groups, sentinels, engine
  -- chains) so saves from older helper layouts migrate forward.
  selector_mode.migrate()
end)

script.on_event(defines.events.on_gui_opened, function(event)
  if event.gui_type ~= defines.gui_type.entity then
    return
  end
  local entity = event.entity
  if not (entity and entity.valid) then
    return
  end
  if entity.type == "constant-combinator" and entity.name == "constant-combinator" then
    cc_gui.open(game.get_player(event.player_index), entity)
  elseif entity.type == "selector-combinator" and entity.name == "selector-combinator" then
    sc_gui.open(game.get_player(event.player_index), entity)
  end
end)

-- Both GUIs listen on the same events; each routes by its tags.lca namespace.
local function fan_out(a, b)
  return function(event)
    a(event)
    b(event)
  end
end

script.on_event(defines.events.on_gui_closed, fan_out(cc_gui.on_gui_closed, sc_gui.on_gui_closed))
script.on_event(defines.events.on_gui_click, fan_out(cc_gui.on_click, sc_gui.on_click))
script.on_event(defines.events.on_gui_elem_changed, fan_out(cc_gui.on_elem_changed, sc_gui.on_elem_changed))
script.on_event(defines.events.on_gui_text_changed, fan_out(cc_gui.on_text_changed, sc_gui.on_text_changed))
script.on_event(defines.events.on_gui_confirmed, cc_gui.on_confirmed)
script.on_event(defines.events.on_gui_checked_state_changed, fan_out(cc_gui.on_checked, sc_gui.on_checked))
script.on_event(defines.events.on_gui_switch_state_changed, cc_gui.on_switch)
script.on_event(defines.events.on_gui_value_changed, cc_gui.on_value_changed)
script.on_event(defines.events.on_object_destroyed, fan_out(cc_gui.on_object_destroyed, sc_gui.on_object_destroyed))
script.on_event(defines.events.on_research_finished, fan_out(preset.on_research_changed, selector_mode.on_research_changed))
script.on_event(defines.events.on_research_reversed, fan_out(preset.on_research_changed, selector_mode.on_research_changed))
script.on_event(defines.events.on_gui_selection_state_changed, fan_out(cc_gui.on_selection, sc_gui.on_selection))
script.on_event(defines.events.on_tick, fan_out(selector_mode.on_tick, persist.on_tick))

-- Build-workflow persistence (#9): blueprints, revival, paste, clone, undo.
local combinator_filter = {
  { filter = "type", type = "constant-combinator" },
  { filter = "type", type = "selector-combinator" },
}
script.on_event(defines.events.on_player_setup_blueprint, persist.on_setup_blueprint)
script.on_event(defines.events.on_built_entity, persist.on_built, combinator_filter)
script.on_event(defines.events.on_robot_built_entity, persist.on_built, combinator_filter)
script.on_event(defines.events.on_space_platform_built_entity, persist.on_built, combinator_filter)
script.on_event(defines.events.script_raised_revive, persist.on_built, combinator_filter)
script.on_event(defines.events.script_raised_built, persist.on_built, combinator_filter)
script.on_event(defines.events.on_entity_settings_pasted, persist.on_settings_pasted)
script.on_event(defines.events.on_entity_cloned, persist.on_cloned, {
  { filter = "type", type = "constant-combinator" },
  { filter = "type", type = "selector-combinator" },
  { filter = "name", name = "lca-hidden-output" },
  { filter = "name", name = "lca-hidden-sentinel" },
  { filter = "name", name = "lca-hidden-anchor" },
  { filter = "name", name = "lca-hidden-merge" },
  { filter = "name", name = "lca-hidden-map" },
  { filter = "name", name = "lca-hidden-gate" },
})
script.on_event(defines.events.on_player_mined_entity, persist.on_player_mined, combinator_filter)
script.on_event(defines.events.on_marked_for_deconstruction, persist.on_marked_for_deconstruction, combinator_filter)
script.on_event(defines.events.on_undo_applied, persist.on_undo_applied)
script.on_event(defines.events.on_redo_applied, persist.on_undo_applied)

-- Scripting API: configure a selector combinator's Mode without the GUI.
-- Lets other mods and headless tooling (bench/, tests) drive the mod.
remote.add_interface("lamented-circuit-additions", {
  --- config = { mode = "vanilla"|"crafting-time"|"memory-cell"|"recipe-products"
  ---   |"recipe-finder", machine = string?, condition = table?,
  ---   researched_only = boolean?, no_fluid = boolean? }
  configure_selector = function(entity, config)
    if not (entity and entity.valid and entity.type == "selector-combinator") then
      error("configure_selector: expected a valid selector-combinator entity")
    end
    config = config or {}
    local mode = config.mode or "vanilla"
    if mode == "vanilla" then
      selector_mode.set_vanilla(entity)
      return
    end
    local state
    if mode == selector_mode.MODE_CRAFTING_TIME then
      state = selector_mode.set_crafting_time(entity)
    elseif mode == selector_mode.MODE_MEMORY_CELL then
      state = selector_mode.set_memory_cell(entity)
      if config.condition then
        state.condition = config.condition
      end
    elseif mode == selector_mode.MODE_RECIPE_PRODUCTS then
      state = selector_mode.set_recipe_products(entity)
    elseif mode == selector_mode.MODE_RECIPE_FINDER then
      state = selector_mode.set_recipe_finder(entity)
      if config.researched_only ~= nil then
        state.researched_only = config.researched_only
      end
      if config.no_fluid ~= nil then
        state.no_fluid = config.no_fluid
      end
    else
      error("configure_selector: unknown mode " .. tostring(mode))
    end
    if config.machine then
      state.machine = config.machine
    end
    -- Recompute (Lua Modes next tick; Crafting-Time rewrites its engine map).
    selector_mode.dirty(entity.unit_number)
  end,
})
