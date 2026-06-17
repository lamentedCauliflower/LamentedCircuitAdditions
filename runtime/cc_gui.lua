-- Replaced GUI for the vanilla constant combinator (ADR-0001).
-- Faithful reproduction of the 2.0 window (status, preview, Output switch,
-- logistic sections with groups/multipliers, numbered slot grid, slot editor,
-- description editor) with one addition: the Mode dropdown.

local preset = require("runtime.preset")
local common = require("runtime.gui_common")

local FRAME_NAME = "lca_cc_frame"
local SLOT_EDITOR_NAME = "lca_cc_slot_editor"
local DESCRIPTION_EDITOR_NAME = "lca_cc_description_editor"
local SLOT_COLUMNS = 10
-- Vanilla sections hold up to 1000 slots; the editor scans/renders this many.
local MAX_SLOT_SCAN = 100
local INT32_MIN, INT32_MAX = -2147483648, 2147483647
local SLIDER_MAX = 1000

local cc_gui = {}

local function states()
  storage.cc_gui = storage.cc_gui or {}
  return storage.cc_gui
end

local destroy_if_present = common.destroy_if_present

function cc_gui.close(player)
  destroy_if_present(player, FRAME_NAME)
  destroy_if_present(player, SLOT_EDITOR_NAME)
  destroy_if_present(player, DESCRIPTION_EDITOR_NAME)
  states()[player.index] = nil
end

-- SignalFilter value -> SpritePath, nil when the sprite type is unknown.
local SPRITE_PREFIX = {
  item = "item/",
  fluid = "fluid/",
  virtual = "virtual-signal/",
  recipe = "recipe/",
  entity = "entity/",
  ["space-location"] = "space-location/",
  ["asteroid-chunk"] = "asteroid-chunk/",
  quality = "quality/",
}

local function sprite_path(value)
  local prefix = SPRITE_PREFIX[value.type or "item"]
  return prefix and (prefix .. value.name) or nil
end

local signal_to_elem = common.signal_to_elem

local function elem_to_filter_value(sig)
  -- A quality-less filter is the "any quality" condition the engine refuses to
  -- pair with a non-zero request — for EVERY signal type, not just items
  -- (virtual/fluid included). Pin a concrete quality (+ "=") so a request is
  -- legal; the engine stores "normal" for symbols that have no quality axis.
  return {
    type = sig.type or "item",
    name = sig.name,
    quality = sig.quality or "normal",
    comparator = "=",
  }
end

local function read_slot(section, index)
  local ok, filter = pcall(section.get_slot, index)
  if ok and filter and filter.value and filter.value.name then
    return filter
  end
  return nil
end

local function section_at(entity, index)
  return entity.get_or_create_control_behavior().sections[index]
end

local function build_titlebar(frame, caption, close_action)
  common.build_titlebar(frame, caption, "cc", close_action)
end

local circuit_status_caption = common.circuit_status_caption
local status_definition = common.status_definition

function cc_gui.refresh_status(player)
  local state = states()[player.index]
  local frame = player.gui.screen[FRAME_NAME]
  if not (state and frame and state.entity and state.entity.valid) then
    return
  end
  local flow = frame.content.inner.status_flow
  local sprite, caption = status_definition(state.entity)
  flow.status_sprite.sprite = sprite
  flow.status_label.caption = caption
end

local function render_slot(tbl, section_index, slot_index, filter)
  local button = tbl.add{
    type = "sprite-button",
    style = "slot_button",
    sprite = filter and sprite_path(filter.value) or nil,
    number = filter and filter.min or nil,
    tags = { lca = "cc", action = "slot", section = section_index, slot = slot_index },
  }
  if filter then
    button.tooltip = { "lca-gui.slot-tooltip" }
  end
end

local function render_section(container, section, section_index, groups, editing)
  -- Header bar: checkbox, group name, rename, (× multiplier), trash.
  local header = container.add{ type = "frame", style = "logistic_section_subheader_frame" }
  header.style.horizontally_stretchable = true
  header.add{
    type = "checkbox",
    state = section.active,
    tooltip = { "lca-gui.section-active" },
    tags = { lca = "cc", action = "section_active", section = section_index },
  }
  local grouped = section.group ~= ""
  header.add{
    type = "label",
    style = "subheader_caption_label",
    caption = grouped and section.group or { "lca-gui.no-group-assigned" },
  }
  header.add{
    type = "sprite-button",
    sprite = "utility/rename_icon",
    style = "mini_button_aligned_to_text_vertically_when_centered",
    tooltip = { "lca-gui.rename-tooltip" },
    tags = { lca = "cc", action = "edit_group", section = section_index },
  }
  local filler = header.add{ type = "empty-widget" }
  filler.style.horizontally_stretchable = true
  if grouped then
    header.add{ type = "label", caption = "×" }
    local multiplier = header.add{
      type = "textfield",
      text = tostring(section.multiplier),
      numeric = true,
      allow_decimal = true,
      allow_negative = false,
      tooltip = { "lca-gui.multiplier-tooltip" },
      tags = { lca = "cc", action = "multiplier", section = section_index },
    }
    multiplier.style.width = 50
  end
  header.add{
    type = "sprite-button",
    sprite = "utility/trash",
    style = "tool_button_red",
    tooltip = { "gui-logistic.remove-logistic-section" },
    tags = { lca = "cc", action = "delete_section", section = section_index },
  }

  -- Group assignment row, shown by the rename button.
  if editing then
    local edit_row = container.add{ type = "flow", direction = "horizontal" }
    edit_row.style.vertical_align = "center"
    local items = { { "lca-gui.no-group" } }
    local selected = 1
    for i, name in ipairs(groups) do
      items[#items + 1] = name
      if name == section.group then
        selected = i + 1
      end
    end
    edit_row.add{
      type = "drop-down",
      items = items,
      selected_index = selected,
      tooltip = { "lca-gui.group-select-tooltip" },
      tags = { lca = "cc", action = "section_group_select", section = section_index, groups = groups },
    }
    local new_group = edit_row.add{
      type = "textfield",
      text = "",
      tooltip = { "lca-gui.new-group-tooltip" },
      tags = { lca = "cc", action = "section_group", section = section_index },
    }
    new_group.style.width = 140
  end

  -- Slot grid, vanilla-style numbered slot buttons.
  local tbl = container.add{ type = "table", style = "filter_slot_table", column_count = SLOT_COLUMNS }
  local filters, last_set = {}, 0
  for i = 1, MAX_SLOT_SCAN do
    local filter = read_slot(section, i)
    if filter then
      filters[i] = filter
      last_set = i
    end
  end
  -- Always at least one full row, then grow a slot past the last set one,
  -- padding to complete rows like vanilla.
  local total = math.min(last_set + 1, MAX_SLOT_SCAN)
  total = math.ceil(total / SLOT_COLUMNS) * SLOT_COLUMNS
  for i = 1, total do
    render_slot(tbl, section_index, i, filters[i])
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
  local sections_frame = frame.content.inner.sections_frame
  if not sections_frame then
    return
  end
  local flow = sections_frame.sections_scroll.sections
  flow.clear()
  local cb = entity.get_or_create_control_behavior()
  local groups = entity.force.get_logistic_groups()
  for i, section in ipairs(cb.sections) do
    render_section(flow, section, i, groups, state.edit_section == i)
  end
end

function cc_gui.open(player, entity)
  cc_gui.close(player)
  states()[player.index] = { entity = entity }
  script.register_on_object_destroyed(entity)

  local frame = player.gui.screen.add{ type = "frame", name = FRAME_NAME, direction = "vertical" }
  frame.style.maximal_height = 800
  build_titlebar(frame, { "entity-name.constant-combinator" }, "close")

  local content = frame.add{
    type = "frame",
    name = "content",
    direction = "vertical",
    style = "inside_shallow_frame",
  }

  local subheader = content.add{ type = "frame", style = "subheader_frame" }
  subheader.style.horizontally_stretchable = true
  subheader.add{ type = "label", style = "subheader_caption_label", caption = circuit_status_caption(entity) }

  local inner = content.add{ type = "flow", name = "inner", direction = "vertical" }
  inner.style.padding = 12
  inner.style.vertical_spacing = 8

  local status_flow = inner.add{ type = "flow", name = "status_flow", direction = "horizontal" }
  status_flow.style.vertical_align = "center"
  local sprite, caption = status_definition(entity)
  status_flow.add{ type = "sprite", name = "status_sprite", sprite = sprite, style = "status_image" }
  status_flow.add{ type = "label", name = "status_label", caption = caption }

  local preview_frame = inner.add{ type = "frame", style = "deep_frame_in_shallow_frame" }
  local preview = preview_frame.add{ type = "entity-preview" }
  preview.style.height = 148
  preview.style.horizontally_stretchable = true
  preview.style.minimal_width = 400
  preview.entity = entity

  local cb = entity.get_or_create_control_behavior()
  inner.add{ type = "label", caption = { "gui-constant.output" }, style = "semibold_label" }
  inner.add{
    type = "switch",
    switch_state = cb.enabled and "right" or "left",
    left_label_caption = { "gui-constant.off" },
    right_label_caption = { "gui-constant.on" },
    tags = { lca = "cc", action = "enabled" },
  }

  -- The one deliberate addition over vanilla (ADR-0001).
  local mode_state = preset.state_for(entity)
  local in_preset = mode_state.mode == preset.MODE_CRAFTABLE_SET
  local mode = inner.add{ type = "flow", direction = "horizontal" }
  mode.style.vertical_align = "center"
  mode.add{ type = "label", caption = { "lca-gui.mode" }, style = "semibold_label" }
  mode.add{
    type = "drop-down",
    items = { { "lca-gui.mode-logistic-groups" }, { "lca-gui.mode-craftable-set" } },
    selected_index = in_preset and 2 or 1,
    tags = { lca = "cc", action = "mode" },
  }

  if in_preset then
    local controls = inner.add{ type = "flow", name = "preset_flow", direction = "vertical" }
    controls.style.vertical_spacing = 8
    local machine_row = controls.add{ type = "flow", direction = "horizontal" }
    machine_row.style.vertical_align = "center"
    machine_row.add{ type = "label", caption = { "lca-gui.machine" } }
    machine_row.add{
      type = "choose-elem-button",
      elem_type = "entity",
      entity = mode_state.machine,
      elem_filters = { { filter = "crafting-machine" } },
      tooltip = { "lca-gui.machine-tooltip" },
      tags = { lca = "cc", action = "preset_machine" },
    }
    controls.add{
      type = "checkbox",
      state = mode_state.researched_only ~= false,
      caption = { "lca-gui.researched-only" },
      tags = { lca = "cc", action = "preset_researched" },
    }
    controls.add{
      type = "checkbox",
      state = mode_state.no_fluid == true,
      caption = { "lca-gui.no-fluid-inputs" },
      tags = { lca = "cc", action = "preset_no_fluid" },
    }
    controls.add{
      type = "label",
      name = "preset_count",
      caption = { "lca-gui.recipe-count", #preset.compute(entity.force, mode_state) },
    }
  else
    local sections_frame = inner.add{
      type = "frame",
      name = "sections_frame",
      direction = "vertical",
      style = "deep_frame_in_shallow_frame",
    }
    local scroll = sections_frame.add{ type = "scroll-pane", name = "sections_scroll" }
    scroll.style.maximal_height = 400
    scroll.style.horizontally_stretchable = true
    scroll.add{ type = "flow", name = "sections", direction = "vertical" }
    local add_button = sections_frame.add{
      type = "button",
      caption = { "gui-logistic.add-section" },
      tags = { lca = "cc", action = "add_section" },
    }
    add_button.style.horizontally_stretchable = true
  end

  inner.add{
    type = "button",
    caption = { "gui-edit-label.add-description" },
    tags = { lca = "cc", action = "edit_description" },
  }

  if not in_preset then
    cc_gui.rebuild_sections(player)
  end

  frame.auto_center = true
  player.opened = frame
end

-- Slot editor: vanilla's "Select a signal" window with count slider.
local function open_slot_editor(player, entity, section_index, slot_index)
  destroy_if_present(player, SLOT_EDITOR_NAME)
  local state = states()[player.index]
  state.slot_editor = { section = section_index, slot = slot_index }

  local section = section_at(entity, section_index)
  local filter = section and read_slot(section, slot_index)

  local frame = player.gui.screen.add{ type = "frame", name = SLOT_EDITOR_NAME, direction = "vertical" }
  build_titlebar(frame, { "gui.select-signal" }, "close_slot_editor")

  local content = frame.add{ type = "frame", direction = "vertical", style = "inside_shallow_frame_with_padding" }
  local row = content.add{ type = "flow", direction = "horizontal" }
  row.style.vertical_align = "center"
  row.add{
    type = "choose-elem-button",
    name = "signal_chooser",
    elem_type = "signal",
    signal = filter and signal_to_elem(filter.value) or nil,
    tags = { lca = "cc", action = "editor_signal" },
  }
  local slider = row.add{
    type = "slider",
    name = "count_slider",
    style = "notched_slider",
    minimum_value = 0,
    maximum_value = SLIDER_MAX,
    value = math.min(math.max(filter and filter.min or 1, 0), SLIDER_MAX),
    tags = { lca = "cc", action = "editor_slider" },
  }
  slider.style.horizontally_stretchable = true
  local count = row.add{
    type = "textfield",
    name = "count_field",
    style = "slider_value_textfield",
    text = tostring(filter and filter.min or 1),
    numeric = true,
    allow_negative = true,
    allow_decimal = false,
    tags = { lca = "cc", action = "editor_count" },
  }
  count.style.width = 60

  local buttons = content.add{ type = "flow", direction = "horizontal" }
  local filler = buttons.add{ type = "empty-widget" }
  filler.style.horizontally_stretchable = true
  buttons.add{
    type = "button",
    style = "confirm_button",
    caption = { "gui.confirm" },
    tags = { lca = "cc", action = "editor_confirm" },
  }

  local main = player.gui.screen[FRAME_NAME]
  local scale = player.display_scale
  frame.location = { main.location.x + math.floor(460 * scale), main.location.y }
end

local function confirm_slot_editor(player, entity)
  local state = states()[player.index]
  local editor = player.gui.screen[SLOT_EDITOR_NAME]
  local target = state.slot_editor
  if not (editor and target) then
    return
  end
  local content = editor.children[2]
  local row = content.children[1]
  local sig = row.signal_chooser.elem_value
  local section = section_at(entity, target.section)
  if section and section.is_manual then
    if sig then
      local n = tonumber(row.count_field.text) or 1
      n = math.max(INT32_MIN, math.min(INT32_MAX, n))
      local ok, err = pcall(section.set_slot, target.slot, { value = elem_to_filter_value(sig), min = n })
      if not ok then
        player.print(err)
      end
    else
      section.clear_slot(target.slot)
    end
  end
  editor.destroy()
  state.slot_editor = nil
  cc_gui.rebuild_sections(player)
end

-- Description editor: vanilla's combinator description window.
local function open_description_editor(player, entity)
  destroy_if_present(player, DESCRIPTION_EDITOR_NAME)
  local frame = player.gui.screen.add{ type = "frame", name = DESCRIPTION_EDITOR_NAME, direction = "vertical" }
  build_titlebar(frame, { "gui-edit-label.edit-description" }, "close_description_editor")
  local content = frame.add{ type = "frame", direction = "vertical", style = "inside_shallow_frame_with_padding" }
  local box = content.add{
    type = "text-box",
    name = "description_box",
    text = entity.combinator_description or "",
  }
  box.style.width = 300
  box.style.height = 120
  local buttons = content.add{ type = "flow", direction = "horizontal" }
  local filler = buttons.add{ type = "empty-widget" }
  filler.style.horizontally_stretchable = true
  buttons.add{
    type = "button",
    style = "confirm_button",
    caption = { "gui.confirm" },
    tags = { lca = "cc", action = "description_confirm" },
  }
  frame.auto_center = true
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

function cc_gui.on_click(event)
  local player, entity, tags = context(event)
  if not player then
    return
  end
  local action = tags.action
  if action == "close" then
    cc_gui.close(player)
  elseif action == "close_slot_editor" then
    destroy_if_present(player, SLOT_EDITOR_NAME)
    states()[player.index].slot_editor = nil
  elseif action == "close_description_editor" then
    destroy_if_present(player, DESCRIPTION_EDITOR_NAME)
  elseif action == "add_section" then
    entity.get_or_create_control_behavior().add_section()
    cc_gui.rebuild_sections(player)
  elseif action == "delete_section" then
    entity.get_or_create_control_behavior().remove_section(tags.section)
    states()[player.index].edit_section = nil
    cc_gui.rebuild_sections(player)
  elseif action == "edit_group" then
    local state = states()[player.index]
    state.edit_section = state.edit_section ~= tags.section and tags.section or nil
    cc_gui.rebuild_sections(player)
  elseif action == "slot" then
    local section = section_at(entity, tags.section)
    if not (section and section.is_manual) then
      return
    end
    if event.button == defines.mouse_button_type.right then
      section.clear_slot(tags.slot)
      cc_gui.rebuild_sections(player)
    else
      open_slot_editor(player, entity, tags.section, tags.slot)
    end
  elseif action == "editor_confirm" then
    confirm_slot_editor(player, entity)
  elseif action == "edit_description" then
    open_description_editor(player, entity)
  elseif action == "description_confirm" then
    local editor = player.gui.screen[DESCRIPTION_EDITOR_NAME]
    if editor then
      entity.combinator_description = editor.children[2].description_box.text
      editor.destroy()
    end
  end
end

-- Recompute the Craftable Set and refresh the recipe-count label.
local function refresh_preset(player, entity)
  local state = preset.state_for(entity)
  local count = preset.apply(entity, state)
  local frame = player.gui.screen[FRAME_NAME]
  local controls = frame and frame.content.inner.preset_flow
  if controls then
    controls.preset_count.caption = { "lca-gui.recipe-count", count }
  end
end

function cc_gui.on_elem_changed(event)
  local player, entity, tags = context(event)
  if not player then
    return
  end
  if tags.action == "preset_machine" then
    preset.state_for(entity).machine = event.element.elem_value
    refresh_preset(player, entity)
  end
  -- "editor_signal" is applied on confirm, like vanilla.
end

function cc_gui.on_value_changed(event)
  local player, _, tags = context(event)
  if not player or tags.action ~= "editor_slider" then
    return
  end
  local editor = player.gui.screen[SLOT_EDITOR_NAME]
  if editor then
    local row = editor.children[2].children[1]
    row.count_field.text = tostring(event.element.slider_value)
  end
end

function cc_gui.on_text_changed(event)
  local player, entity, tags = context(event)
  if not player then
    return
  end
  local n = tonumber(event.element.text)
  if tags.action == "editor_count" then
    local editor = player.gui.screen[SLOT_EDITOR_NAME]
    if editor and n then
      local row = editor.children[2].children[1]
      row.count_slider.slider_value = math.min(math.max(n, 0), SLIDER_MAX)
    end
  elseif tags.action == "multiplier" then
    local section = section_at(entity, tags.section)
    if section and section.is_manual and n and n >= 0 then
      section.multiplier = n
    end
  end
end

function cc_gui.on_confirmed(event)
  local player, entity, tags = context(event)
  if not player or tags.action ~= "section_group" then
    return
  end
  local name = event.element.text
  local section = section_at(entity, tags.section)
  if section and section.is_manual and name ~= "" then
    entity.force.create_logistic_group(name)
    section.group = name
    states()[player.index].edit_section = nil
    cc_gui.rebuild_sections(player)
  end
end

function cc_gui.on_checked(event)
  local player, entity, tags = context(event)
  if not player then
    return
  end
  if tags.action == "section_active" then
    local section = section_at(entity, tags.section)
    if section and section.is_manual then
      section.active = event.element.state
    end
  elseif tags.action == "preset_researched" then
    preset.state_for(entity).researched_only = event.element.state
    refresh_preset(player, entity)
  elseif tags.action == "preset_no_fluid" then
    preset.state_for(entity).no_fluid = event.element.state
    refresh_preset(player, entity)
  end
end

function cc_gui.on_switch(event)
  local player, entity, tags = context(event)
  if not player or tags.action ~= "enabled" then
    return
  end
  entity.get_or_create_control_behavior().enabled = event.element.switch_state == "right"
  cc_gui.refresh_status(player)
end

function cc_gui.on_selection(event)
  local player, entity, tags = context(event)
  if not player then
    return
  end
  if tags.action == "mode" then
    local target = event.element.selected_index == 2
      and preset.MODE_CRAFTABLE_SET
      or preset.MODE_LOGISTIC_GROUPS
    if preset.state_for(entity).mode ~= target then
      preset.set_mode(entity, target)
      -- Rebuild the whole window around the new Mode.
      cc_gui.open(player, entity)
    end
    return
  end
  if tags.action == "section_group_select" then
    local section = section_at(entity, tags.section)
    if not (section and section.is_manual) then
      return
    end
    local index = event.element.selected_index
    if index <= 1 then
      section.group = ""
    else
      local name = (tags.groups or {})[index - 1]
      if name then
        section.group = name
      end
    end
    states()[player.index].edit_section = nil
    cc_gui.rebuild_sections(player)
  end
end

-- Close every window still pointing at a combinator that no longer exists
-- (mined, destroyed, killed by script — anything), and drop the destroyed
-- combinator's Mode state.
function cc_gui.on_object_destroyed(event)
  if event.type == defines.target_type.entity and event.useful_id then
    preset.forget(event.useful_id)
  end
  for player_index, state in pairs(states()) do
    if not (state.entity and state.entity.valid) then
      local player = game.get_player(player_index)
      if player then
        cc_gui.close(player)
      end
    end
  end
end

function cc_gui.on_gui_closed(event)
  local element = event.element
  if element and element.valid and element.name == FRAME_NAME then
    cc_gui.close(game.get_player(event.player_index))
  end
end

return cc_gui
