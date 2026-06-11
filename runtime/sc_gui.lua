-- Replaced GUI for the vanilla selector combinator (ADR-0001).
-- Faithful reproduction of the 2.0 window (status, preview, operation
-- dropdown with per-operation settings, description editor). The unified
-- dropdown is where the mod's selector Modes get appended later.

local common = require("runtime.gui_common")
local selector_mode = require("runtime.selector_mode")

local FRAME_NAME = "lca_sc_frame"
local DESCRIPTION_EDITOR_NAME = "lca_sc_description_editor"
local INT32_MAX = 2147483647

-- Vanilla dropdown order.
local OPERATIONS = {
  "select",
  "count",
  "random",
  "stack-size",
  "rocket-capacity",
  "quality-transfer",
  "quality-filter",
}
local OP_INDEX = {}
for i, op in ipairs(OPERATIONS) do
  OP_INDEX[op] = i
end

-- Script-driven Modes appended after the vanilla operations.
local CT_DROPDOWN_INDEX = #OPERATIONS + 1

-- Vanilla circuit-condition comparator order; the engine reports the
-- canonical single-character forms.
local COMPARATORS = { "<", ">", "=", "≥", "≤", "≠" }
local CANONICAL_COMPARATOR = { [">="] = "≥", ["<="] = "≤", ["!="] = "≠" }

local sc_gui = {}

local function states()
  storage.sc_gui = storage.sc_gui or {}
  return storage.sc_gui
end

function sc_gui.close(player)
  common.destroy_if_present(player, FRAME_NAME)
  common.destroy_if_present(player, DESCRIPTION_EDITOR_NAME)
  states()[player.index] = nil
end

local function parameters(entity)
  return entity.get_or_create_control_behavior().parameters or {}
end

-- Read-modify-write the whole parameters table; the engine validates on
-- assignment, so surface its message instead of crashing.
local function update_parameters(player, entity, mutate)
  local cb = entity.get_or_create_control_behavior()
  local params = cb.parameters or {}
  mutate(params)
  local ok, err = pcall(function()
    cb.parameters = params
  end)
  if not ok then
    player.print(err)
  end
end

local function comparator_of(value)
  return CANONICAL_COMPARATOR[value] or value or "="
end

-- The engine hands quality back as a string, a table, or a prototype
-- object; everything but a string has a .name.
local function quality_name_of(value)
  if type(value) == "string" then
    return value
  end
  return value and value.name or nil
end

-- quality_filter may come back as a string shorthand or a table. The
-- engine refuses a quality_filter write without a comparator key, so one
-- is always present here.
local function quality_filter_of(params)
  local qf = params.quality_filter
  if type(qf) == "string" then
    qf = { quality = qf }
  elseif type(qf) == "table" then
    qf = { quality = quality_name_of(qf.quality), comparator = qf.comparator }
  else
    qf = {}
  end
  qf.comparator = comparator_of(qf.comparator)
  return qf
end

-- Visible qualities, lowest level first, for the static quality pickers.
local function quality_list()
  local list = {}
  for name, proto in pairs(prototypes.quality) do
    if not proto.hidden then
      list[#list + 1] = { name = name, level = proto.level, localised = proto.localised_name }
    end
  end
  table.sort(list, function(a, b)
    return a.level < b.level
  end)
  return list
end

-- Dropdown of quality prototypes (no quality ElemType exists). The picked
-- names ride along in tags; "" stands for "any quality".
local function add_quality_dropdown(parent, selected_name, action, include_any)
  local items, names, selected = {}, {}, 1
  if include_any then
    items[1] = { "lca-gui.any-quality" }
    names[1] = ""
  end
  for _, quality in ipairs(quality_list()) do
    items[#items + 1] = { "", "[quality=" .. quality.name .. "] ", quality.localised }
    names[#items] = quality.name
    if quality.name == selected_name then
      selected = #items
    end
  end
  return parent.add{
    type = "drop-down",
    items = items,
    selected_index = selected,
    tags = { lca = "sc", action = action, names = names },
  }
end

local function labeled_row(parent)
  local row = parent.add{ type = "flow", direction = "horizontal" }
  row.style.vertical_align = "center"
  row.style.horizontal_spacing = 8
  return row
end

-- Per-operation settings panels, captions straight from gui-selector.

local function build_select_panel(panel, params)
  panel.add{
    type = "radiobutton",
    state = params.select_max ~= false,
    caption = { "gui-selector.select-max" },
    tooltip = { "gui-selector.select-sort-description" },
    tags = { lca = "sc", action = "select_sort", max = true },
  }
  panel.add{
    type = "radiobutton",
    state = params.select_max == false,
    caption = { "gui-selector.select-min" },
    tooltip = { "gui-selector.select-sort-description" },
    tags = { lca = "sc", action = "select_sort", max = false },
  }
  local row = labeled_row(panel)
  row.add{ type = "label", caption = { "gui-selector.index" }, style = "semibold_label" }
  row.add{
    type = "choose-elem-button",
    elem_type = "signal",
    signal = common.signal_to_elem(params.index_signal),
    tags = { lca = "sc", action = "index_signal" },
  }
  -- Engine index is 0-based; vanilla displays it 1-based.
  local constant = row.add{
    type = "textfield",
    text = tostring((params.index_constant or 0) + 1),
    numeric = true,
    allow_decimal = false,
    allow_negative = false,
    enabled = params.index_signal == nil,
    tags = { lca = "sc", action = "index_constant" },
  }
  constant.style.width = 60
end

local function build_count_panel(panel, params)
  local row = labeled_row(panel)
  row.add{ type = "label", caption = { "gui-selector.count-output" }, style = "semibold_label" }
  row.add{
    type = "choose-elem-button",
    elem_type = "signal",
    signal = common.signal_to_elem(params.count_signal),
    tags = { lca = "sc", action = "count_signal" },
  }
end

local function build_random_panel(panel, params)
  local row = labeled_row(panel)
  row.add{ type = "label", caption = { "gui-selector.random-interval" }, style = "semibold_label" }
  local interval = row.add{
    type = "textfield",
    text = tostring(params.random_update_interval or 0),
    numeric = true,
    allow_decimal = false,
    allow_negative = false,
    tags = { lca = "sc", action = "random_interval" },
  }
  interval.style.width = 80
end

local function build_quality_transfer_panel(panel, params)
  local from_signal = params.select_quality_from_signal == true
  panel.add{
    type = "radiobutton",
    state = not from_signal,
    caption = { "gui-selector.quality-source-static" },
    tags = { lca = "sc", action = "qt_source", from_signal = false },
  }
  local static_row = labeled_row(panel)
  local static_picker = add_quality_dropdown(
    static_row,
    quality_name_of(params.quality_source_static) or "normal",
    "qt_static_quality",
    false
  )
  static_picker.enabled = not from_signal
  panel.add{
    type = "radiobutton",
    state = from_signal,
    caption = { "gui-selector.quality-source-signal" },
    tooltip = { "gui-selector.quality-source-signal-description" },
    tags = { lca = "sc", action = "qt_source", from_signal = true },
  }
  local signal_row = labeled_row(panel)
  local source_signal = signal_row.add{
    type = "choose-elem-button",
    elem_type = "signal",
    signal = common.signal_to_elem(params.quality_source_signal),
    tags = { lca = "sc", action = "qt_source_signal" },
  }
  source_signal.enabled = from_signal
  local target_row = labeled_row(panel)
  target_row.add{ type = "label", caption = { "gui-selector.quality-destination" }, style = "semibold_label" }
  target_row.add{
    type = "choose-elem-button",
    elem_type = "signal",
    signal = common.signal_to_elem(params.quality_destination_signal),
    tags = { lca = "sc", action = "qt_destination" },
  }
end

local function build_quality_filter_panel(panel, params)
  local qf = quality_filter_of(params)
  local row = labeled_row(panel)
  local comparator = comparator_of(qf.comparator)
  local selected = 3
  for i, c in ipairs(COMPARATORS) do
    if c == comparator then
      selected = i
    end
  end
  local picker = row.add{
    type = "drop-down",
    items = COMPARATORS,
    selected_index = selected,
    tags = { lca = "sc", action = "qf_comparator" },
  }
  picker.style.width = 60
  add_quality_dropdown(row, qf.quality, "qf_quality", true)
end

local function build_crafting_time_panel(panel, state)
  local row = labeled_row(panel)
  row.add{ type = "label", caption = { "lca-gui.machine" }, style = "semibold_label" }
  row.add{
    type = "choose-elem-button",
    elem_type = "entity",
    entity = state.machine,
    elem_filters = { { filter = "crafting-machine" } },
    tooltip = { "lca-gui.machine-tooltip" },
    tags = { lca = "sc", action = "ct_machine" },
  }
end

local PANEL_BUILDERS = {
  ["select"] = build_select_panel,
  ["count"] = build_count_panel,
  ["random"] = build_random_panel,
  ["quality-transfer"] = build_quality_transfer_panel,
  ["quality-filter"] = build_quality_filter_panel,
  -- stack-size and rocket-capacity have no settings.
}

function sc_gui.open(player, entity)
  sc_gui.close(player)
  states()[player.index] = { entity = entity }
  script.register_on_object_destroyed(entity)

  local frame = player.gui.screen.add{ type = "frame", name = FRAME_NAME, direction = "vertical" }
  frame.style.maximal_height = 800
  common.build_titlebar(frame, { "entity-name.selector-combinator" }, "sc", "close")

  local content = frame.add{
    type = "frame",
    name = "content",
    direction = "vertical",
    style = "inside_shallow_frame",
  }

  local subheader = content.add{ type = "frame", style = "subheader_frame" }
  subheader.style.horizontally_stretchable = true
  subheader.add{ type = "label", style = "subheader_caption_label", caption = common.circuit_status_caption(entity) }

  local inner = content.add{ type = "flow", name = "inner", direction = "vertical" }
  inner.style.padding = 12
  inner.style.vertical_spacing = 8

  local status_flow = inner.add{ type = "flow", direction = "horizontal" }
  status_flow.style.vertical_align = "center"
  local sprite, caption = common.status_definition(entity)
  status_flow.add{ type = "sprite", sprite = sprite, style = "status_image" }
  status_flow.add{ type = "label", caption = caption }

  local preview_frame = inner.add{ type = "frame", style = "deep_frame_in_shallow_frame" }
  local preview = preview_frame.add{ type = "entity-preview" }
  preview.style.height = 148
  preview.style.horizontally_stretchable = true
  preview.style.minimal_width = 400
  preview.entity = entity

  local params = parameters(entity)
  local op = params.operation or "select"
  local mode_state = selector_mode.state_of(entity)
  local in_ct = mode_state and mode_state.mode == selector_mode.MODE_CRAFTING_TIME

  local items = {}
  for i, name in ipairs(OPERATIONS) do
    items[i] = { "gui-selector." .. name }
  end
  items[CT_DROPDOWN_INDEX] = { "lca-gui.mode-crafting-time" }
  local dropdown = inner.add{
    type = "drop-down",
    items = items,
    selected_index = in_ct and CT_DROPDOWN_INDEX or OP_INDEX[op] or 1,
    tags = { lca = "sc", action = "operation" },
  }
  dropdown.style.horizontally_stretchable = true

  local description = inner.add{
    type = "label",
    caption = in_ct and { "lca-gui.mode-crafting-time-description" }
      or { "gui-selector." .. op .. "-description" },
  }
  description.style.single_line = false
  description.style.maximal_width = 400

  local panel = inner.add{ type = "flow", name = "panel", direction = "vertical" }
  panel.style.vertical_spacing = 8
  if in_ct then
    build_crafting_time_panel(panel, mode_state)
  else
    local builder = PANEL_BUILDERS[op]
    if builder then
      builder(panel, params)
    end
  end

  inner.add{
    type = "button",
    caption = { "gui-edit-label.add-description" },
    tags = { lca = "sc", action = "edit_description" },
  }

  frame.auto_center = true
  player.opened = frame
end

local function reopen(player, entity)
  local location = player.gui.screen[FRAME_NAME] and player.gui.screen[FRAME_NAME].location
  sc_gui.open(player, entity)
  if location then
    player.gui.screen[FRAME_NAME].location = location
  end
end

-- Description editor: vanilla's combinator description window.
local function open_description_editor(player, entity)
  common.destroy_if_present(player, DESCRIPTION_EDITOR_NAME)
  local frame = player.gui.screen.add{ type = "frame", name = DESCRIPTION_EDITOR_NAME, direction = "vertical" }
  common.build_titlebar(frame, { "gui-edit-label.edit-description" }, "sc", "close_description_editor")
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
    tags = { lca = "sc", action = "description_confirm" },
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
  if tags.lca ~= "sc" then
    return
  end
  local player = game.get_player(event.player_index)
  local state = states()[event.player_index]
  if not (player and state) then
    return
  end
  local entity = state.entity
  if not (entity and entity.valid) then
    sc_gui.close(player)
    return
  end
  return player, entity, tags
end

function sc_gui.on_click(event)
  local player, entity, tags = context(event)
  if not player then
    return
  end
  local action = tags.action
  if action == "close" then
    sc_gui.close(player)
  elseif action == "close_description_editor" then
    common.destroy_if_present(player, DESCRIPTION_EDITOR_NAME)
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

function sc_gui.on_selection(event)
  local player, entity, tags = context(event)
  if not player then
    return
  end
  local action = tags.action
  local index = event.element.selected_index
  if action == "operation" then
    if index == CT_DROPDOWN_INDEX then
      selector_mode.set_crafting_time(entity)
    else
      selector_mode.set_vanilla(entity)
      update_parameters(player, entity, function(p)
        p.operation = OPERATIONS[index] or "select"
      end)
    end
    reopen(player, entity)
  elseif action == "qf_comparator" then
    update_parameters(player, entity, function(p)
      local qf = quality_filter_of(p)
      qf.comparator = COMPARATORS[index] or "="
      p.quality_filter = qf
    end)
  elseif action == "qf_quality" then
    local name = (tags.names or {})[index]
    update_parameters(player, entity, function(p)
      local qf = quality_filter_of(p)
      qf.quality = name ~= "" and name or nil
      p.quality_filter = qf
    end)
  elseif action == "qt_static_quality" then
    local name = (tags.names or {})[index]
    if name and name ~= "" then
      update_parameters(player, entity, function(p)
        -- The engine silently drops every other BlueprintQualityID shape.
        p.quality_source_static = { name = name }
      end)
    end
  end
end

function sc_gui.on_checked(event)
  local player, entity, tags = context(event)
  if not player then
    return
  end
  if tags.action == "select_sort" then
    update_parameters(player, entity, function(p)
      p.select_max = tags.max
    end)
    reopen(player, entity)
  elseif tags.action == "qt_source" then
    update_parameters(player, entity, function(p)
      p.select_quality_from_signal = tags.from_signal
    end)
    reopen(player, entity)
  end
end

function sc_gui.on_elem_changed(event)
  local player, entity, tags = context(event)
  if not player then
    return
  end
  local action = tags.action
  local sig = event.element.elem_value
  if action == "ct_machine" then
    selector_mode.set_machine(entity, sig)
  elseif action == "index_signal" then
    update_parameters(player, entity, function(p)
      p.index_signal = sig
    end)
    reopen(player, entity)
  elseif action == "count_signal" then
    update_parameters(player, entity, function(p)
      p.count_signal = sig
    end)
  elseif action == "qt_source_signal" then
    update_parameters(player, entity, function(p)
      p.quality_source_signal = sig
    end)
  elseif action == "qt_destination" then
    update_parameters(player, entity, function(p)
      p.quality_destination_signal = sig
    end)
  end
end

function sc_gui.on_text_changed(event)
  local player, entity, tags = context(event)
  if not player then
    return
  end
  local n = tonumber(event.element.text)
  if not n then
    return
  end
  if tags.action == "index_constant" then
    update_parameters(player, entity, function(p)
      p.index_constant = math.max(1, math.min(INT32_MAX, n)) - 1
    end)
  elseif tags.action == "random_interval" then
    update_parameters(player, entity, function(p)
      p.random_update_interval = math.max(0, math.min(INT32_MAX, n))
    end)
  end
end

-- Close every window still pointing at a combinator that no longer exists,
-- and tear down the destroyed combinator's script Mode (hidden output).
function sc_gui.on_object_destroyed(event)
  if event.type == defines.target_type.entity and event.useful_id then
    selector_mode.forget(event.useful_id)
  end
  for player_index, state in pairs(states()) do
    if not (state.entity and state.entity.valid) then
      local player = game.get_player(player_index)
      if player then
        sc_gui.close(player)
      end
    end
  end
end

function sc_gui.on_gui_closed(event)
  local element = event.element
  if element and element.valid and element.name == FRAME_NAME then
    sc_gui.close(game.get_player(event.player_index))
  end
end

return sc_gui
