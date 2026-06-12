-- Script-driven Modes for the selector combinator. The engine cannot run
-- custom selector operations, so while a script Mode is active the vanilla
-- selector is parked inert and deactivated (entity.active = false) and a
-- hidden constant combinator, wired to the selector's output connectors,
-- carries the script-computed signals. All state lives in storage keyed by
-- unit number.
--
-- Per-tick budget: bulk signal reads (get_signals) cost ~20µs per call, a
-- scalar read costs ~0.4µs. So a hidden sentinel arithmetic combinator
-- watches each script combinator's input networks and folds them into one
-- signal (each XOR K -> S); the engine keeps it current event-driven. The
-- per-tick driver reads that one scalar, and only on a sentinel change (or
-- a staggered full sweep every SWEEP_INTERVAL ticks, the safety net for
-- XOR-sum collisions) does it read the full frame, recompute, and rewrite
-- the hidden output. Configuration setters mark the state dirty with
-- state.last_output = nil to force a recompute on the next tick.

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
local SENTINEL_ENTITY = "lca-hidden-sentinel"
local SENTINEL_SIGNAL = { type = "virtual", name = "signal-S" }
local SENTINEL_MIX = 1515870810 -- 0x5A5A5A5A, mixes values so natural sum-preserving moves still register
local SWEEP_INTERVAL = 30
local INT32_MIN, INT32_MAX = -2147483648, 2147483647
local INERT_PARAMETERS = { operation = "count" }
local IN_RED = defines.wire_connector_id.combinator_input_red
local IN_GREEN = defines.wire_connector_id.combinator_input_green
local EMPTY = {} -- shared "no input networks" frame

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

--- Drop the force's cached researched set and mark the force's Recipe
--- Finders dirty so they recompute even with an unchanged input frame.
function selector_mode.on_research_changed(event)
  local force = event.research.force
  researched_cache[force.index] = nil
  for _, state in pairs(mode_states()) do
    if state.mode == selector_mode.MODE_RECIPE_FINDER then
      local entity = state.entity
      if entity and entity.valid and entity.force.index == force.index then
        state.last_output = nil
      end
    end
  end
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

-- Sentinel control behaviors, a module-local cache rebuilt lazily per load
-- (LuaObject lookups are deterministic, so this is multiplayer-safe).
local sentinel_cbs = {}

local function ensure_sentinel(entity, state)
  if state.sentinel and state.sentinel.valid then
    return state.sentinel
  end
  sentinel_cbs[entity.unit_number] = nil
  local sentinel = entity.surface.create_entity{
    name = SENTINEL_ENTITY,
    position = entity.position,
    force = entity.force,
  }
  sentinel.destructible = false
  for _, id in ipairs({ IN_RED, IN_GREEN }) do
    local selector_side = entity.get_wire_connector(id, true)
    local sentinel_side = sentinel.get_wire_connector(id, true)
    sentinel_side.connect_to(selector_side, false, defines.wire_origin.script)
  end
  sentinel.get_or_create_control_behavior().parameters = {
    first_signal = { type = "virtual", name = "signal-each" },
    operation = "XOR",
    second_constant = SENTINEL_MIX,
    output_signal = SENTINEL_SIGNAL,
  }
  state.sentinel = sentinel
  state.sentinel_value = nil
  return sentinel
end

local function destroy_helpers(state)
  if state.output and state.output.valid then
    state.output.destroy()
  end
  state.output = nil
  if state.sentinel and state.sentinel.valid then
    state.sentinel.destroy()
  end
  state.sentinel = nil
end

-- Enter a script Mode. Coming from engine-driven: stash the vanilla
-- parameters, park the selector inert and deactivated, attach the hidden
-- output and sentinel. Switching between script Modes keeps the stash and
-- the helpers. Returns the state and whether the Mode actually changed.
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
  -- The engine never needs to update the parked selector; the hidden
  -- output carries the signals.
  entity.active = false
  ensure_output(entity, state)
  ensure_sentinel(entity, state)
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

--- Back to engine-driven: drop the script helpers, reactivate the selector
--- and restore the stashed vanilla parameters. No-op when no script Mode
--- is active.
function selector_mode.set_vanilla(entity)
  local all = mode_states()
  local state = all[entity.unit_number]
  if not state then
    return
  end
  destroy_helpers(state)
  entity.active = true
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
    destroy_helpers(state)
    sentinel_cbs[unit_number] = nil
    local entity = state.entity
    if entity and entity.valid then
      entity.active = true
    end
    mode_states()[unit_number] = nil
  end
end

-- Red and green inputs summed per (type, name, quality) by the engine in
-- one call; the merged array's order is stable while the networks' content
-- is unchanged.
local function input_signals(entity)
  return entity.get_signals(IN_RED, IN_GREEN) or EMPTY
end

-- Element-wise equality of two engine signal arrays ({ signal, count }).
-- String equality is interned-pointer comparison, so this allocates
-- nothing. A reordered-but-equal frame compares unequal, which only costs
-- a redundant recompute, never a wrong output.
local function inputs_equal(a, b)
  if a == b then
    return true
  end
  if type(b) ~= "table" or #a ~= #b then
    return false
  end
  for i = 1, #a do
    local sa, sb = a[i], b[i]
    if sa.count ~= sb.count then
      return false
    end
    local va, vb = sa.signal, sb.signal
    if
      va.name ~= vb.name
      or (va.type or "item") ~= (vb.type or "item")
      or (va.quality or "normal") ~= (vb.quality or "normal")
    then
      return false
    end
  end
  return true
end

-- Element-wise equality of two domain output frames
-- ({ type, name, quality, count }, deterministically sorted).
local function outputs_equal(a, b)
  if type(b) ~= "table" or #a ~= #b then
    return false
  end
  for i = 1, #a do
    local ea, eb = a[i], b[i]
    if
      ea.count ~= eb.count
      or ea.name ~= eb.name
      or (ea.type or "item") ~= (eb.type or "item")
      or (ea.quality or "normal") ~= (eb.quality or "normal")
    then
      return false
    end
  end
  return true
end

-- Engine signal array -> domain input frame. Only runs on change ticks.
local function to_frame(signals)
  local frame = {}
  for i = 1, #signals do
    local signal = signals[i]
    local id = signal.signal
    frame[i] = {
      type = id.type or "item",
      name = id.name,
      quality = id.quality or "normal",
      count = signal.count,
    }
  end
  return frame
end

local function write_output(entity, state, out)
  local output = ensure_output(entity, state)
  local cb = output.get_or_create_control_behavior()
  local section = cb.get_section(1) or cb.add_section()
  local filters = {}
  for i = 1, #out do
    local signal = out[i]
    local count = signal.count
    if count > INT32_MAX then
      count = INT32_MAX
    elseif count < INT32_MIN then
      count = INT32_MIN
    end
    filters[i] = {
      value = {
        type = signal.type or "item",
        name = signal.name,
        quality = signal.quality or "normal",
        comparator = "=",
      },
      min = count,
    }
  end
  local ok, err = pcall(function()
    section.filters = filters
  end)
  if not ok then
    log(err)
  end
end

local function compute_crafting_time(state, signals)
  local speed = machine_speed(state.machine)
  if not (speed and speed > 0) then
    return {}
  end
  return crafting_time.map(to_frame(signals), energies(), speed)
end

local function compute_recipe_products(state, signals)
  return recipe_products.map(to_frame(signals), products())
end

local function compute_recipe_finder(state, signals)
  local categories = machine_categories(state.machine)
  if not categories then
    return {}
  end
  return recipe_finder.find(
    to_frame(signals),
    producer_index(),
    categories,
    {
      researched_only = state.researched_only ~= false,
      no_fluid_inputs = state.no_fluid == true,
    },
    researched_set(state.entity.force)
  )
end

-- One tick of the Memory Cell; level-triggered, so the step itself decides
-- whether the Stored Frame is replaced or kept. An unchanged input frame
-- always yields an unchanged Stored Frame, so the change gating upstream
-- is exact for this Mode too.
local function compute_memory_cell(state, signals)
  state.stored = memory_cell.step(state.stored or {}, to_frame(signals), state.condition)
  return state.stored
end

local COMPUTE = {
  [selector_mode.MODE_CRAFTING_TIME] = compute_crafting_time,
  [selector_mode.MODE_MEMORY_CELL] = compute_memory_cell,
  [selector_mode.MODE_RECIPE_PRODUCTS] = compute_recipe_products,
  [selector_mode.MODE_RECIPE_FINDER] = compute_recipe_finder,
}

-- Full re-evaluation: read the merged frame, recompute when it differs
-- from the previous one (or the state is dirty), rewrite the hidden output
-- when the result actually changed.
local function drive(entity, state, compute)
  local signals = input_signals(entity)
  if state.last_output and inputs_equal(signals, state.last_input) then
    return
  end
  state.last_input = signals
  local out = compute(state, signals)
  if state.last_output and outputs_equal(out, state.last_output) then
    state.last_output = out
    return
  end
  write_output(entity, state, out)
  state.last_output = out
end

function selector_mode.on_tick()
  local states = storage.sc_modes
  if not states or next(states) == nil then
    return
  end
  local tick = game.tick
  for unit_number, state in pairs(states) do
    local compute = COMPUTE[state.mode]
    if compute then
      local entity = state.entity
      if entity and entity.valid then
        local sentinel = state.sentinel
        if sentinel and sentinel.valid then
          local cb = sentinel_cbs[unit_number]
          if not cb then
            cb = sentinel.get_or_create_control_behavior()
            sentinel_cbs[unit_number] = cb
          end
          local value = cb.get_signal_last_tick(SENTINEL_SIGNAL) or 0
          if
            value == state.sentinel_value
            and state.last_output
            and (tick + unit_number) % SWEEP_INTERVAL ~= 0
          then
            -- Steady state: input unchanged per the sentinel, no sweep
            -- due, nothing forced a rewrite.
            goto continue
          end
          state.sentinel_value = value
        else
          ensure_sentinel(entity, state)
        end
        drive(entity, state, compute)
      else
        selector_mode.forget(unit_number)
      end
    end
    ::continue::
  end
end

return selector_mode
