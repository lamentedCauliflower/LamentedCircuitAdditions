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

script.on_event(defines.events.on_gui_opened, function(event)
  if event.gui_type ~= defines.gui_type.entity then
    return
  end
  local entity = event.entity
  if not (entity and entity.valid) then
    return
  end
  if entity.type == "constant-combinator" then
    cc_gui.open(game.get_player(event.player_index), entity)
  elseif entity.type == "selector-combinator" then
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
})
script.on_event(defines.events.on_player_mined_entity, persist.on_player_mined, combinator_filter)
script.on_event(defines.events.on_marked_for_deconstruction, persist.on_marked_for_deconstruction, combinator_filter)
script.on_event(defines.events.on_undo_applied, persist.on_undo_applied)
script.on_event(defines.events.on_redo_applied, persist.on_undo_applied)
