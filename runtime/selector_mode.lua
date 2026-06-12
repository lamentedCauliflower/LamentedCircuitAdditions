-- Script-driven Modes for the selector combinator. The engine cannot run
-- custom selector operations, so while a script Mode is active the vanilla
-- selector is parked inert ("count" with no output signal emits nothing)
-- and a hidden constant combinator, wired to the selector's output
-- connectors, carries the script-computed signals. All state lives in
-- storage keyed by unit number; the per-tick driver only rewrites the
-- hidden combinator when the output frame actually changes.

local crafting_time = require("domain.crafting_time")
local memory_cell = require("domain.memory_cell")
local recipe_products = require("domain.recipe_products")
local recipe_finder = require("domain.recipe_finder")
local preset = require("runtime.preset")

local selector_mode = {}

selector_mode.MODE_CRAFTING_TIME = "crafting-time"
selector_mode.MODE_MEMORY_CELL = "memory-cell"
selector_mode.MODE_RECIPE_PRODUCTS = "recipe-products"
selector_mode.MODE_RECIPE_FINDER = "recipe-finder"

local OUTPUT_ENTITY = "lca-hidden-output"
local INT32_MIN, INT32_MAX = -2147483648, 2147483647
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

-- Item and fluid products per recipe with their raw amount fields, rebuilt
-- once per load from prototypes (deterministic, multiplayer-safe). The
-- nominal-amount rule lives in the domain module.
local products_cache
local function products()
  if not products_cache then
    products_cache = {}
    for name, proto in pairs(prototypes.recipe) do
      local list = {}
      for _, product in ipairs(proto.products or {}) do
        if product.type == "item" or product.type == "fluid" then
          list[#list + 1] = {
            type = product.type,
            name = product.name,
            amount = product.amount,
            amount_min = product.amount_min,
            amount_max = product.amount_max,
          }
        end
      end
      products_cache[name] = list
    end
  end
  return products_cache
end

-- Producer index for the Recipe Finder, rebuilt once per load from
-- prototypes (deterministic, multiplayer-safe).
local finder_index
local function producer_index()
  if not finder_index then
    local recipes = {}
    for name, proto in pairs(prototypes.recipe) do
      local product_list = {}
      for _, product in ipairs(proto.products or {}) do
        if product.type == "item" or product.type == "fluid" then
          product_list[#product_list + 1] = { type = product.type, name = product.name }
        end
      end
      local main = proto.main_product
      local has_fluid = false
      for _, ingredient in pairs(proto.ingredients or {}) do
        if ingredient.type == "fluid" then
          has_fluid = true
          break
        end
      end
      recipes[#recipes + 1] = {
        name = name,
        category = proto.category,
        hidden = proto.hidden,
        parameter = proto.parameter,
        has_fluid_ingredient = has_fluid,
        products = product_list,
        main_product = main and { type = main.type, name = main.name } or nil,
      }
    end
    finder_index = recipe_finder.index(recipes)
  end
  return finder_index
end

local function machine_categories(machine_name)
  local proto = machine_name and prototypes.entity[machine_name]
  return proto and proto.crafting_categories or nil
end

-- Researched recipe names per force index, rebuilt lazily and invalidated
-- on research changes. Derived deterministically from game state, so a
-- module-local cache is multiplayer-safe.
local researched_cache = {}
local function researched_set(force)
  local set = researched_cache[force.index]
  if not set then
    set = {}
    for name, recipe in pairs(force.recipes) do
      if recipe.enabled then
        set[name] = true
      end
    end
    researched_cache[force.index] = set
  end
  return set
end

--- Drop the force's cached researched set; the per-tick driver rebuilds it
--- and rewrites any Recipe Finder output that changed.
function selector_mode.on_research_changed(event)
  researched_cache[event.research.force.index] = nil
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

-- Enter a script Mode. Coming from engine-driven: stash the vanilla
-- parameters, park the selector inert and attach the hidden output.
-- Switching between script Modes keeps the stash and the hidden output.
-- Returns the state and whether the Mode actually changed.
local function enter_script_mode(entity, mode)
  local all = mode_states()
  local state = all[entity.unit_number]
  if state then
    state.entity = entity
    if state.mode == mode then
      return state, false
    end
    state.mode = mode
    state.last_output = nil
    return state, true
  end
  local cb = entity.get_or_create_control_behavior()
  state = {
    mode = mode,
    entity = entity,
    stash = cb.parameters,
  }
  all[entity.unit_number] = state
  cb.parameters = INERT_PARAMETERS
  ensure_output(entity, state)
  script.register_on_object_destroyed(entity)
  return state, true
end

function selector_mode.set_crafting_time(entity)
  local state = enter_script_mode(entity, selector_mode.MODE_CRAFTING_TIME)
  if state.machine == nil then
    state.machine = preset.default_machine()
  end
  return state
end

function selector_mode.set_recipe_products(entity)
  return enter_script_mode(entity, selector_mode.MODE_RECIPE_PRODUCTS)
end

function selector_mode.set_recipe_finder(entity)
  local state = enter_script_mode(entity, selector_mode.MODE_RECIPE_FINDER)
  if state.machine == nil then
    state.machine = preset.default_machine()
  end
  if state.researched_only == nil then
    state.researched_only = true
  end
  if state.no_fluid == nil then
    state.no_fluid = false
  end
  return state
end

--- Update a Recipe Finder Filter and force a rewrite on the next tick.
function selector_mode.set_filter(entity, filter, value)
  local state = mode_states()[entity.unit_number]
  if state then
    state[filter] = value
    state.last_output = nil
  end
end

function selector_mode.set_memory_cell(entity)
  local state, changed = enter_script_mode(entity, selector_mode.MODE_MEMORY_CELL)
  if changed then
    state.stored = {}
  end
  state.condition = state.condition or { comparator = "<", constant = 0 }
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

--- Manually clear the Memory Cell's Stored Frame.
function selector_mode.clear_memory(entity)
  local state = mode_states()[entity.unit_number]
  if state and state.mode == selector_mode.MODE_MEMORY_CELL then
    state.stored = {}
    -- Force a rewrite on the next tick.
    state.last_output = nil
  end
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
    parts[i] = (signal.type or "item") .. "/" .. signal.name .. "/" .. (signal.quality or "") .. "=" .. signal.count
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
      value = {
        type = signal.type or "item",
        name = signal.name,
        quality = signal.quality or "normal",
        comparator = "=",
      },
      min = math.max(INT32_MIN, math.min(signal.count, INT32_MAX)),
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

local function drive_recipe_products(entity, state)
  local out = recipe_products.map(merged_input_frame(entity), products())
  local current = signature(out)
  if current ~= state.last_output then
    state.last_output = current
    write_output(entity, state, out)
  end
end

local function drive_recipe_finder(entity, state)
  local out = {}
  local categories = machine_categories(state.machine)
  if categories then
    out = recipe_finder.find(
      merged_input_frame(entity),
      producer_index(),
      categories,
      {
        researched_only = state.researched_only ~= false,
        no_fluid_inputs = state.no_fluid == true,
      },
      researched_set(entity.force)
    )
  end
  local current = signature(out)
  if current ~= state.last_output then
    state.last_output = current
    write_output(entity, state, out)
  end
end

local function drive_memory_cell(entity, state)
  state.stored = memory_cell.step(state.stored or {}, merged_input_frame(entity), state.condition)
  local current = signature(state.stored)
  if current ~= state.last_output then
    state.last_output = current
    write_output(entity, state, state.stored)
  end
end

local DRIVERS = {
  [selector_mode.MODE_CRAFTING_TIME] = drive_crafting_time,
  [selector_mode.MODE_MEMORY_CELL] = drive_memory_cell,
  [selector_mode.MODE_RECIPE_PRODUCTS] = drive_recipe_products,
  [selector_mode.MODE_RECIPE_FINDER] = drive_recipe_finder,
}

function selector_mode.on_tick()
  for unit_number, state in pairs(mode_states()) do
    local driver = DRIVERS[state.mode]
    if driver then
      local entity = state.entity
      if entity and entity.valid then
        driver(entity, state)
      else
        selector_mode.forget(unit_number)
      end
    end
  end
end

return selector_mode
