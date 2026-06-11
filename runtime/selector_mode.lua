-- Script-driven Modes for the selector combinator. The engine cannot run
-- custom selector operations, so while a script Mode is active the vanilla
-- selector is parked inert ("count" with no output signal emits nothing)
-- and a hidden constant combinator, wired to the selector's output
-- connectors, carries the script-computed signals. All state lives in
-- storage keyed by unit number; the per-tick driver only rewrites the
-- hidden combinator when the output frame actually changes.

local crafting_time = require("domain.crafting_time")
local preset = require("runtime.preset")

local selector_mode = {}

selector_mode.MODE_CRAFTING_TIME = "crafting-time"

local OUTPUT_ENTITY = "lca-hidden-output"
local INT32_MAX = 2147483647
local INERT_PARAMETERS = { operation = "count" }

local function mode_states()
  storage.sc_modes = storage.sc_modes or {}
  return storage.sc_modes
end

--- The combinator's script-Mode state, or nil when engine-driven.
function selector_mode.state_of(entity)
  return mode_states()[entity.unit_number]
end

-- Recipe energies, rebuilt once per load from prototypes (deterministic,
-- so a plain module-local cache is multiplayer-safe).
local energy_cache
local function energies()
  if not energy_cache then
    energy_cache = {}
    for name, proto in pairs(prototypes.recipe) do
      energy_cache[name] = proto.energy
    end
  end
  return energy_cache
end

local function machine_speed(machine_name)
  local proto = machine_name and prototypes.entity[machine_name]
  if not proto then
    return nil
  end
  local ok, speed = pcall(function()
    return proto.get_crafting_speed()
  end)
  if ok then
    return speed
  end
  return nil
end

local function ensure_output(entity, state)
  if state.output and state.output.valid then
    return state.output
  end
  local output = entity.surface.create_entity{
    name = OUTPUT_ENTITY,
    position = entity.position,
    force = entity.force,
  }
  output.destructible = false
  local connector = defines.wire_connector_id
  for _, pair in ipairs({
    { connector.combinator_output_red, connector.circuit_red },
    { connector.combinator_output_green, connector.circuit_green },
  }) do
    local selector_side = entity.get_wire_connector(pair[1], true)
    local output_side = output.get_wire_connector(pair[2], true)
    output_side.connect_to(selector_side, false, defines.wire_origin.script)
  end
  state.output = output
  return output
end

local function destroy_output(state)
  if state.output and state.output.valid then
    state.output.destroy()
  end
  state.output = nil
end

--- Enter Crafting-Time Mode: stash the vanilla parameters, park the
--- selector inert and attach the hidden output. No-op when already active.
function selector_mode.set_crafting_time(entity)
  local all = mode_states()
  local state = all[entity.unit_number]
  if state and state.mode == selector_mode.MODE_CRAFTING_TIME then
    state.entity = entity
    return state
  end
  local cb = entity.get_or_create_control_behavior()
  state = {
    mode = selector_mode.MODE_CRAFTING_TIME,
    entity = entity,
    machine = preset.default_machine(),
    stash = cb.parameters,
  }
  all[entity.unit_number] = state
  cb.parameters = INERT_PARAMETERS
  ensure_output(entity, state)
  script.register_on_object_destroyed(entity)
  return state
end

--- Back to engine-driven: drop the script output and restore the stashed
--- vanilla parameters. No-op when no script Mode is active.
function selector_mode.set_vanilla(entity)
  local all = mode_states()
  local state = all[entity.unit_number]
  if not state then
    return
  end
  destroy_output(state)
  local cb = entity.get_or_create_control_behavior()
  local ok = pcall(function()
    cb.parameters = state.stash
  end)
  if not ok then
    cb.parameters = nil
  end
  all[entity.unit_number] = nil
end

function selector_mode.set_machine(entity, machine_name)
  local state = mode_states()[entity.unit_number]
  if state then
    state.machine = machine_name
    -- Force a rewrite on the next tick.
    state.last_output = nil
  end
end

function selector_mode.forget(unit_number)
  local state = mode_states()[unit_number]
  if state then
    destroy_output(state)
    mode_states()[unit_number] = nil
  end
end

-- Red and green inputs summed per (type, name, quality), insertion-ordered.
local function merged_input_frame(entity)
  local connector = defines.wire_connector_id
  local merged, frame = {}, {}
  for _, id in ipairs({ connector.combinator_input_red, connector.combinator_input_green }) do
    local network = entity.get_circuit_network(id)
    for _, signal in ipairs(network and network.signals or {}) do
      local value = signal.signal
      local kind = value.type or "item"
      local key = kind .. "/" .. value.name .. "/" .. (value.quality or "normal")
      local entry = merged[key]
      if entry then
        entry.count = entry.count + signal.count
      else
        entry = { type = kind, name = value.name, quality = value.quality or "normal", count = signal.count }
        merged[key] = entry
        frame[#frame + 1] = entry
      end
    end
  end
  return frame
end

local function signature(out)
  local parts = {}
  for i, signal in ipairs(out) do
    parts[i] = signal.name .. "/" .. (signal.quality or "") .. "=" .. signal.count
  end
  return table.concat(parts, ";")
end

local function write_output(entity, state, out)
  local output = ensure_output(entity, state)
  local cb = output.get_or_create_control_behavior()
  while cb.sections_count > 0 do
    cb.remove_section(1)
  end
  local section = cb.add_section()
  local filters = {}
  for i, signal in ipairs(out) do
    filters[i] = {
      value = { type = "recipe", name = signal.name, quality = signal.quality or "normal", comparator = "=" },
      min = math.min(signal.count, INT32_MAX),
    }
  end
  local ok, err = pcall(function()
    section.filters = filters
  end)
  if not ok then
    log(err)
  end
end

local function drive_crafting_time(entity, state)
  local out = {}
  local speed = machine_speed(state.machine)
  if speed and speed > 0 then
    out = crafting_time.map(merged_input_frame(entity), energies(), speed)
  end
  local current = signature(out)
  if current ~= state.last_output then
    state.last_output = current
    write_output(entity, state, out)
  end
end

function selector_mode.on_tick()
  for unit_number, state in pairs(mode_states()) do
    if state.mode == selector_mode.MODE_CRAFTING_TIME then
      local entity = state.entity
      if entity and entity.valid then
        drive_crafting_time(entity, state)
      else
        selector_mode.forget(unit_number)
      end
    end
  end
end

return selector_mode
