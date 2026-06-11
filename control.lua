-- Runtime entry point. Factorio API access lives here and in runtime/;
-- decision logic belongs in pure modules under domain/.
local cc_gui = require("runtime.cc_gui")
local sc_gui = require("runtime.sc_gui")
local preset = require("runtime.preset")

script.on_init(function()
  storage.cc_gui = {}
  storage.cc_modes = {}
  storage.sc_gui = {}
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
script.on_event(defines.events.on_research_finished, preset.on_research_changed)
script.on_event(defines.events.on_research_reversed, preset.on_research_changed)
script.on_event(defines.events.on_gui_selection_state_changed, fan_out(cc_gui.on_selection, sc_gui.on_selection))