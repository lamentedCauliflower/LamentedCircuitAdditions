-- Widgets and captions shared by the replaced combinator GUIs (ADR-0001).
local common = {}

function common.destroy_if_present(player, name)
  local frame = player.gui.screen[name]
  if frame then
    frame.destroy()
  end
end

-- Titlebar shared by all mod windows. `namespace` is the tags.lca value the
-- owning module routes its events by.
function common.build_titlebar(frame, caption, namespace, close_action)
  local bar = frame.add{ type = "flow", direction = "horizontal" }
  bar.drag_target = frame
  bar.add{ type = "label", caption = caption, style = "frame_title", ignored_by_interaction = true }
  local drag = bar.add{ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true }
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  bar.add{
    type = "sprite-button",
    sprite = "utility/close",
    style = "frame_action_button",
    tags = { lca = namespace, action = close_action },
  }
end

function common.circuit_status_caption(entity)
  local connector = defines.wire_connector_id
  local red = entity.get_circuit_network(connector.circuit_red)
  local green = entity.get_circuit_network(connector.circuit_green)
  if not (red or green) then
    return { "gui.not-connected" }
  end
  local caption = { "", { "gui-control-behavior.circuit-network" }, ":" }
  if red then
    caption[#caption + 1] = " [color=red]" .. red.network_id .. "[/color]"
  end
  if green then
    caption[#caption + 1] = " [color=green]" .. green.network_id .. "[/color]"
  end
  return caption
end

function common.status_definition(entity)
  local status = entity.status
  if status == defines.entity_status.working then
    return "utility/status_working", { "entity-status.working" }
  end
  if status == defines.entity_status.no_power then
    return "utility/status_not_working", { "entity-status.no-power" }
  end
  if status == defines.entity_status.low_power then
    return "utility/status_yellow", { "entity-status.low-power" }
  end
  return "utility/status_yellow", { "entity-status.disabled" }
end

-- SignalID -> choose-elem-button "signal" value, nil-safe.
function common.signal_to_elem(value)
  if not (value and value.name) then
    return nil
  end
  return { type = value.type or "item", name = value.name, quality = value.quality }
end

return common
