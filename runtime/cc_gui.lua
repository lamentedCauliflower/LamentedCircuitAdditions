-- Replaced GUI for the vanilla constant combinator (ADR-0001).
-- Vanilla Mode only: a Mode dropdown stub plus a reimplementation of the
-- 2.0 logistic-sections editor, applied directly to the entity's control
-- behavior. No mod-specific behavior yet.

local FRAME_NAME = "lca_cc_frame"
local SLOT_COLUMNS = 10
-- Vanilla sections hold up to 1000 slots; the editor scans/render this many.
local MAX_SLOT_SCAN = 100
local INT32_MIN, INT32_MAX = -2147483648, 2147483647

local cc_gui = {}

local function states()
  storage.cc_gui = storage.cc_gui or {}
  return storage.cc_gui
end

function cc_gui.close(player)
  local frame = player.gui.screen[FRAME_NAME]
  if frame then
    frame.destroy()
  end
  states()[player.index] = nil
end

local function signal_to_elem(value)
  if not (value and value.name) then
    return nil
  end
  return { type = value.type or "item", name = value.name, quality = value.quality }
end

local function elem_to_filter_value(sig)
  local value = { type = sig.type or "item", name = sig.name }
  if sig.quality then
    value.quality = sig.quality
  end
  return value
end

local function read_slot(section, index)
  local ok, filter = pcall(section.get_slot, index)
  if ok and filter and filter.value and filter.value.name then
    return filter
  end
  return nil
end

local function add_slot_cell(tbl, section_index, slot_index, filter)
  local cell = tbl.add{ type = "flow", direction = "vertical" }
  cell.add{
    type = "choose-elem-button",
    elem_type = "signal",
    signal = filter and signal_to_elem(filter.value) or nil,
    tags = { lca = "cc", action = "slot", section = section_index, slot = slot_index },
  }
  local count = cell.add{
    type = "textfield",
    text = filter and tostring(filter.min or 0) or "",
    numeric = true,
    allow_negative = true,
    allow_decimal = false,
    enabled = filter ~= nil,
    tooltip = { "lca-gui.count-tooltip" },
    tags = { lca = "cc", action = "count", section = section_index, slot = slot_index },
  }
  count.style.width = 40
  count.style.horizontal_align = "center"
end

local function render_section(container, section, section_index)
  local sec_frame = container.add{ type = "frame", direction = "vertical", style = "bordered_frame" }

  local header = sec_frame.add{ type = "flow", direction = "horizontal" }
  header.style.vertical_align = "center"
  header.add{
    type = "checkbox",
    state = section.active,
    tooltip = { "lca-gui.section-active" },
    tags = { lca = "cc", action = "section_active", section = section_index },
  }
  local group = header.add{
    type = "textfield",
    text = section.group or "",
    tooltip = { "lca-gui.group-tooltip" },
    tags = { lca = "cc", action = "section_group", section = section_index },
  }
  group.style.width = 160
  local filler = header.add{ type = "empty-widget" }
  filler.style.horizontally_stretchable = true
  header.add{
    type = "sprite-button",
    sprite = "utility/trash",
    style = "tool_button_red",
    tooltip = { "lca-gui.delete-section" },
    tags = { lca = "cc", action = "delete_section", section = section_index },
  }

  local tbl = sec_frame.add{ type = "table", column_count = SLOT_COLUMNS }
  local filters, last_set = {}, 0
  for i = 1, MAX_SLOT_SCAN do
    local filter = read_slot(section, i)
    if filter then
      filters[i] = filter
      last_set = i
    end
  end
  for i = 1, math.min(last_set + 1, MAX_SLOT_SCAN) do
    add_slot_cell(tbl, section_index, i, filters[i])
  end
end

function cc_gui.rebuild_sections(player)
  local state = states()[player.index]
  local frame = player.gui.screen[FRAME_NAME]
  if not (state and frame) then
    return
  end
  local entity = state.entity
  if not (entity and entity.valid) then
    return cc_gui.close(player)
  end
  local flow = frame.content.sections_scroll.sections
  flow.clear()
  local cb = entity.get_or_create_control_behavior()
  for i, section in ipairs(cb.sections) do
    render_section(flow, section, i)
  end
end

function cc_gui.open(player, entity)
  cc_gui.close(player)

  local frame = player.gui.screen.add{
    type = "frame",
    name = FRAME_NAME,
    direction = "vertical",
  }

  local titlebar = frame.add{ type = "flow", direction = "horizontal" }
  titlebar.drag_target = frame
  titlebar.add{
    type = "label",
    caption = { "entity-name.constant-combinator" },
    style = "frame_title",
    ignored_by_interaction = true,
  }
  local drag = titlebar.add{ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true }
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  titlebar.add{
    type = "sprite-button",
    sprite = "utility/close",
    style = "frame_action_button",
    tags = { lca = "cc", action = "close" },
  }

  states()[player.index] = { entity = entity }

  local cb = entity.get_or_create_control_behavior()
  local content = frame.add{
    type = "frame",
    name = "content",
    direction = "vertical",
    style = "inside_shallow_frame_with_padding",
  }

  local top = content.add{ type = "flow", direction = "horizontal" }
  top.style.vertical_align = "center"
  top.add{ type = "label", caption = { "lca-gui.enabled" } }
  top.add{
    type = "switch",
    switch_state = cb.enabled and "right" or "left",
    left_label_caption = { "lca-gui.off" },
    right_label_caption = { "lca-gui.on" },
    tags = { lca = "cc", action = "enabled" },
  }

  local mode = content.add{ type = "flow", direction = "horizontal" }
  mode.style.vertical_align = "center"
  mode.add{ type = "label", caption = { "lca-gui.mode" } }
  mode.add{
    type = "drop-down",
    items = { { "lca-gui.mode-vanilla" } },
    selected_index = 1,
    tags = { lca = "cc", action = "mode" },
  }

  local scroll = content.add{ type = "scroll-pane", name = "sections_scroll" }
  scroll.style.maximal_height = 600
  scroll.add{ type = "flow", name = "sections", direction = "vertical" }

  content.add{
    type = "button",
    caption = { "lca-gui.add-section" },
    tags = { lca = "cc", action = "add_section" },
  }

  cc_gui.rebuild_sections(player)

  frame.auto_center = true
  player.opened = frame
end

-- Returns player, entity, tags when the event element belongs to this GUI
-- and the edited combinator is still valid; closes the GUI otherwise.
local function context(event)
  local element = event.element
  if not (element and element.valid) then
    return
  end
  local tags = element.tags
  if tags.lca ~= "cc" then
    return
  end
  local player = game.get_player(event.player_index)
  local state = states()[event.player_index]
  if not (player and state) then
    return
  end
  local entity = state.entity
  if not (entity and entity.valid) then
    cc_gui.close(player)
    return
  end
  return player, entity, tags
end

local function section_at(entity, index)
  return entity.get_or_create_control_behavior().sections[index]
end

function cc_gui.on_click(event)
  local player, entity, tags = context(event)
  if not player then
    return
  end
  if tags.action == "close" then
    cc_gui.close(player)
  elseif tags.action == "add_section" then
    entity.get_or_create_control_behavior().add_section()
    cc_gui.rebuild_sections(player)
  elseif tags.action == "delete_section" then
    entity.get_or_create_control_behavior().remove_section(tags.section)
    cc_gui.rebuild_sections(player)
  end
end

function cc_gui.on_elem_changed(event)
  local player, entity, tags = context(event)
  if not player or tags.action ~= "slot" then
    return
  end
  local section = section_at(entity, tags.section)
  if not section then
    return cc_gui.rebuild_sections(player)
  end
  local sig = event.element.elem_value
  if sig then
    local previous = read_slot(section, tags.slot)
    section.set_slot(tags.slot, {
      value = elem_to_filter_value(sig),
      min = previous and previous.min or 1,
    })
  else
    section.clear_slot(tags.slot)
  end
  cc_gui.rebuild_sections(player)
end

function cc_gui.on_text_changed(event)
  local player, entity, tags = context(event)
  if not player or tags.action ~= "count" then
    return
  end
  local n = tonumber(event.element.text)
  if not n then
    return
  end
  n = math.max(INT32_MIN, math.min(INT32_MAX, n))
  local section = section_at(entity, tags.section)
  local filter = section and read_slot(section, tags.slot)
  if filter then
    filter.min = n
    section.set_slot(tags.slot, filter)
  end
end

function cc_gui.on_confirmed(event)
  local player, entity, tags = context(event)
  if not player or tags.action ~= "section_group" then
    return
  end
  local section = section_at(entity, tags.section)
  if section then
    section.group = event.element.text
    cc_gui.rebuild_sections(player)
  end
end

function cc_gui.on_checked(event)
  local player, entity, tags = context(event)
  if not player or tags.action ~= "section_active" then
    return
  end
  local section = section_at(entity, tags.section)
  if section then
    section.active = event.element.state
  end
end

function cc_gui.on_switch(event)
  local player, entity, tags = context(event)
  if not player or tags.action ~= "enabled" then
    return
  end
  entity.get_or_create_control_behavior().enabled = event.element.switch_state == "right"
end

function cc_gui.on_selection(event)
  local player, _, tags = context(event)
  if not player or tags.action ~= "mode" then
    return
  end
  -- Single "Vanilla" entry in this slice; Presets arrive with the next one.
end

function cc_gui.on_gui_closed(event)
  local element = event.element
  if element and element.valid and element.name == FRAME_NAME then
    cc_gui.close(game.get_player(event.player_index))
  end
end

return cc_gui
