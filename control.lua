-- Runtime entry point. Factorio API access lives here and in runtime/;
-- decision logic belongs in pure modules under domain/.
local cc_gui = require("runtime.cc_gui")

script.on_init(function()
  storage.cc_gui = {}
end)

script.on_event(defines.events.on_gui_opened, function(event)
  if event.gui_type ~= defines.gui_type.entity then
    return
  end
  local entity = event.entity
  if not (entity and entity.valid and entity.type == "constant-combinator") then
    return
  end
  cc_gui.open(game.get_player(event.player_index), entity)
end)

script.on_event(defines.events.on_gui_closed, cc_gui.on_gui_closed)
script.on_event(defines.events.on_gui_click, cc_gui.on_click)
script.on_event(defines.events.on_gui_elem_changed, cc_gui.on_elem_changed)
script.on_event(defines.events.on_gui_text_changed, cc_gui.on_text_changed)
script.on_event(defines.events.on_gui_confirmed, cc_gui.on_confirmed)
script.on_event(defines.events.on_gui_checked_state_changed, cc_gui.on_checked)
script.on_event(defines.events.on_gui_switch_state_changed, cc_gui.on_switch)
script.on_event(defines.events.on_gui_value_changed, cc_gui.on_value_changed)
script.on_event(defines.events.on_gui_selection_state_changed, cc_gui.on_selection)
