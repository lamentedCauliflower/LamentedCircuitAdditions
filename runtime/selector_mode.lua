-- Script-driven Modes for the selector combinator. The engine cannot run
-- custom selector operations, so while a script Mode is active the vanilla
-- selector is parked inert and deactivated (entity.disabled_by_script = true) and hidden
-- helper entities, wired to the selector's connectors, carry the work. All
-- state lives in storage keyed by unit number.
--
-- Two strategies, by Mode:
--
-- * Crafting-Time is fully engine-driven (zero per-tick Lua). A hidden chain
--   merge (arith) -> map (constant) -> gate (decider) reproduces the mapping:
--   merge collapses the host's red+green inputs onto one wire; map holds every
--   recipe's crafting-tick count for the Target Machine; gate emits each recipe
--   present on the merged input with the count copied from map. Rewritten only
--   on Target-Machine / config change.
--
-- * Memory Cell, Recipe Products and Recipe Finder still run a per-tick Lua
--   driver, but cheaply. Bulk signal reads (get_signals) cost ~20us; a scalar
--   read ~0.4us. So a hidden sentinel arithmetic combinator folds each host's
--   inputs into one signal (each XOR K -> S), kept current event-driven. The
--   sentinels of up to GROUP_MAX same-surface hosts feed one hidden anchor
--   (S + 0 -> S) that sums them. Per tick the driver reads each group's anchor
--   scalar; an unchanged sum (and no sweep / forced flag) skips the whole
--   group without touching its members. On a change it reads each member's own
--   sentinel to find which moved and drives only those. A staggered per-group
--   sweep every SWEEP_INTERVAL ticks is the safety net for XOR-sum collisions.

local ticks = require("domain.ticks")
local memory_cell = require("domain.memory_cell")
local recipe_products = require("domain.recipe_products")
local recipe_finder = require("domain.recipe_finder")
local stack_pack = require("domain.stack_pack")
local preset = require("runtime.preset")

local selector_mode = {}

selector_mode.MODE_CRAFTING_TIME = "crafting-time"
selector_mode.MODE_MEMORY_CELL = "memory-cell"
selector_mode.MODE_RECIPE_PRODUCTS = "recipe-products"
selector_mode.MODE_RECIPE_FINDER = "recipe-finder"
selector_mode.MODE_STACK_PACK = "stack-pack"

local OUTPUT_ENTITY = "lca-hidden-output"
local SENTINEL_ENTITY = "lca-hidden-sentinel"
local ANCHOR_ENTITY = "lca-hidden-anchor"
local MERGE_ENTITY = "lca-hidden-merge"
local MAP_ENTITY = "lca-hidden-map"
local GATE_ENTITY = "lca-hidden-gate"
local SENTINEL_SIGNAL = { type = "virtual", name = "signal-S" }
local EACH = { type = "virtual", name = "signal-each" }
local SENTINEL_MIX = 1515870810 -- 0x5A5A5A5A, mixes values so natural sum-preserving moves still register
local SWEEP_INTERVAL = 60
local GROUP_MAX = 32
local INT32_MIN, INT32_MAX = -2147483648, 2147483647
local MAX_SECTION_FILTERS = 1000
local INERT_PARAMETERS = { operation = "count" }
local IN_RED = defines.wire_connector_id.combinator_input_red
local IN_GREEN = defines.wire_connector_id.combinator_input_green
local OUT_RED = defines.wire_connector_id.combinator_output_red
local OUT_GREEN = defines.wire_connector_id.combinator_output_green
local CIRCUIT_GREEN = defines.wire_connector_id.circuit_green
local EMPTY = {} -- shared "no input networks" frame

local function mode_states()
  storage.sc_modes = storage.sc_modes or {}
  return storage.sc_modes
end

local function groups()
  storage.sc_groups = storage.sc_groups or {}
  return storage.sc_groups
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

-- Item stack sizes, rebuilt once per load from prototypes (deterministic,
-- multiplayer-safe). Feeds the Stack Pack Mode's slot arithmetic.
local stack_size_cache
local function stack_sizes()
  if not stack_size_cache then
    stack_size_cache = {}
    for name, proto in pairs(prototypes.item) do
      stack_size_cache[name] = proto.stack_size
    end
  end
  return stack_size_cache
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

-- Visible quality names, deterministically sorted, for building the
-- crafting-time map across qualities (a recipe signal keeps its quality).
local quality_cache
local function quality_names()
  if not quality_cache then
    quality_cache = {}
    for name in pairs(prototypes.quality) do
      quality_cache[#quality_cache + 1] = name
    end
    table.sort(quality_cache)
  end
  return quality_cache
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

-- Bound sentinel/anchor reader functions (control_behavior.get_signal_last_tick),
-- module-local caches rebuilt lazily per load. Caching the bound method skips
-- the LuaObject __index lookup on every steady tick; deterministic, so
-- multiplayer-safe. sentinel_reads keyed by unit number, anchor_reads by group id.
local sentinel_reads = {}
local anchor_reads = {}

local function spawn(entity, name)
  local helper = entity.surface.create_entity{
    name = name,
    position = entity.position,
    force = entity.force,
  }
  helper.destructible = false
  return helper
end

-- Script-origin wire between two entities' connectors.
local function connect(a, a_conn, b, b_conn)
  local ca = a.get_wire_connector(a_conn, true)
  local cb = b.get_wire_connector(b_conn, true)
  ca.connect_to(cb, false, defines.wire_origin.script)
end

local function ensure_output(entity, state)
  if state.output and state.output.valid then
    return state.output
  end
  local output = spawn(entity, OUTPUT_ENTITY)
  local connector = defines.wire_connector_id
  connect(output, connector.circuit_red, entity, connector.combinator_output_red)
  connect(output, connector.circuit_green, entity, connector.combinator_output_green)
  state.output = output
  return output
end

local function ensure_sentinel(entity, state)
  if state.sentinel and state.sentinel.valid then
    return state.sentinel
  end
  sentinel_reads[entity.unit_number] = nil
  local sentinel = spawn(entity, SENTINEL_ENTITY)
  connect(sentinel, IN_RED, entity, IN_RED)
  connect(sentinel, IN_GREEN, entity, IN_GREEN)
  sentinel.get_or_create_control_behavior().parameters = {
    first_signal = EACH,
    operation = "XOR",
    second_constant = SENTINEL_MIX,
    output_signal = SENTINEL_SIGNAL,
  }
  state.sentinel = sentinel
  state.sentinel_value = nil
  return sentinel
end

-- ---- Crafting-Time engine chain ------------------------------------------

-- Write the map constant combinator: every recipe -> its crafting-tick count
-- for the Target Machine, across all qualities. Rewritten on machine/config
-- change only. An invalid machine leaves the map empty (gate emits nothing).
local function write_ct_map(state)
  local map = state.map
  if not (map and map.valid) then
    return
  end
  local cb = map.get_or_create_control_behavior()
  while cb.sections_count > 0 do
    cb.remove_section(cb.sections_count)
  end
  local speed = machine_speed(state.machine)
  if not (speed and speed > 0) then
    return
  end
  local quals = quality_names()
  local names = {}
  for name in pairs(energies()) do
    names[#names + 1] = name
  end
  table.sort(names)
  local en = energies()
  -- One flat filter list, then chunked into sections (filter order is
  -- irrelevant: the network sums per signal).
  local filters = {}
  for _, name in ipairs(names) do
    local count = ticks.crafting_ticks(en[name], speed)
    if count > INT32_MAX then
      count = INT32_MAX
    elseif count < INT32_MIN then
      count = INT32_MIN
    end
    for _, q in ipairs(quals) do
      filters[#filters + 1] = {
        value = { type = "recipe", name = name, quality = q, comparator = "=" },
        min = count,
      }
    end
  end
  for start = 1, #filters, MAX_SECTION_FILTERS do
    local chunk = {}
    for i = start, math.min(start + MAX_SECTION_FILTERS - 1, #filters) do
      chunk[#chunk + 1] = filters[i]
    end
    local section = cb.add_section()
    local ok, err = pcall(function()
      section.filters = chunk
    end)
    if not ok then
      log(err)
    end
  end
end

local function ensure_ct_helpers(entity, state)
  if not (state.merge and state.merge.valid) then
    local merge = spawn(entity, MERGE_ENTITY)
    connect(merge, IN_RED, entity, IN_RED)
    connect(merge, IN_GREEN, entity, IN_GREEN)
    merge.get_or_create_control_behavior().parameters = {
      first_signal = EACH,
      operation = "+",
      second_constant = 0,
      output_signal = EACH,
    }
    state.merge = merge
  end
  if not (state.map and state.map.valid) then
    state.map = spawn(entity, MAP_ENTITY)
  end
  if not (state.gate and state.gate.valid) then
    local gate = spawn(entity, GATE_ENTITY)
    -- Condition reads the merged user frame (red); output copies counts from
    -- the map (green). A recipe present on red but absent from map yields
    -- count 0 and is dropped, so non-recipe inputs fall away naturally.
    connect(gate, IN_RED, state.merge, OUT_RED)
    connect(gate, IN_GREEN, state.map, CIRCUIT_GREEN)
    connect(gate, OUT_RED, entity, OUT_RED)
    connect(gate, OUT_GREEN, entity, OUT_GREEN)
    gate.get_or_create_control_behavior().parameters = {
      conditions = {
        {
          first_signal = EACH,
          comparator = "≠",
          constant = 0,
          first_signal_networks = { red = true, green = false },
        },
      },
      outputs = {
        {
          signal = EACH,
          copy_count_from_input = true,
          networks = { red = false, green = true },
        },
      },
    }
    state.gate = gate
  end
end

-- ---- Group lifecycle (Lua-driven Modes) ----------------------------------

local function new_group(entity)
  local all = groups()
  storage.sc_group_seq = (storage.sc_group_seq or 0) + 1
  local gid = storage.sc_group_seq
  local anchor = spawn(entity, ANCHOR_ENTITY)
  anchor.get_or_create_control_behavior().parameters = {
    first_signal = SENTINEL_SIGNAL,
    operation = "+",
    second_constant = 0,
    output_signal = SENTINEL_SIGNAL,
  }
  local group = {
    anchor = anchor,
    surface = entity.surface.index,
    members = {},
    count = 0,
    last_sum = nil,
    forced = true,
  }
  all[gid] = group
  anchor_reads[gid] = nil
  return gid, group
end

-- Add a Lua-driven member to a same-surface group (creating one when none has
-- room), wiring its sentinel output onto the group's shared anchor network.
local function ensure_group(state)
  local entity = state.entity
  local un = entity.unit_number
  local all = groups()
  if state.group_id then
    local g = all[state.group_id]
    if g and g.anchor and g.anchor.valid and g.members[un] then
      g.forced = true
      return g
    end
  end
  local surface = entity.surface.index
  local gid, group
  for id, g in pairs(all) do
    if g.surface == surface and g.count < GROUP_MAX and g.anchor and g.anchor.valid then
      gid, group = id, g
      break
    end
  end
  if not group then
    gid, group = new_group(entity)
  end
  group.members[un] = true
  group.count = group.count + 1
  group.forced = true
  state.group_id = gid
  connect(state.sentinel, OUT_RED, group.anchor, IN_RED)
  return group
end

local function leave_group(state, un)
  local gid = state.group_id
  state.group_id = nil
  if not gid then
    return
  end
  local all = storage.sc_groups
  local g = all and all[gid]
  if not g then
    return
  end
  if g.members[un] then
    g.members[un] = nil
    g.count = g.count - 1
  end
  if g.count <= 0 then
    if g.anchor and g.anchor.valid then
      g.anchor.destroy()
    end
    anchor_reads[gid] = nil
    all[gid] = nil
  end
end

local function destroy_helpers(state, un)
  un = un or (state.entity and state.entity.unit_number)
  for _, field in ipairs({ "output", "sentinel", "merge", "map", "gate" }) do
    local helper = state[field]
    if helper and helper.valid then
      helper.destroy()
    end
    state[field] = nil
  end
  if un then
    sentinel_reads[un] = nil
  end
  leave_group(state, un)
end

-- Enter a script Mode. Coming from engine-driven: stash the vanilla
-- parameters, park the selector inert and deactivated. Switching between
-- script Modes drops the old Mode's helpers (the setter builds the new ones).
-- Returns the state and whether the Mode actually changed.
local function enter_script_mode(entity, mode)
  local all = mode_states()
  local state = all[entity.unit_number]
  if state then
    state.entity = entity
    if state.mode == mode then
      return state, false
    end
    destroy_helpers(state, entity.unit_number)
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
  -- The engine never needs to update the parked selector; the helpers carry
  -- the signals.
  entity.disabled_by_script = true
  script.register_on_object_destroyed(entity)
  return state, true
end

local function ensure_lua_helpers(entity, state)
  ensure_output(entity, state)
  ensure_sentinel(entity, state)
  ensure_group(state)
end

function selector_mode.set_crafting_time(entity)
  local state = enter_script_mode(entity, selector_mode.MODE_CRAFTING_TIME)
  if state.machine == nil then
    state.machine = preset.default_machine()
  end
  ensure_ct_helpers(entity, state)
  write_ct_map(state)
  return state
end

function selector_mode.set_recipe_products(entity)
  local state = enter_script_mode(entity, selector_mode.MODE_RECIPE_PRODUCTS)
  ensure_lua_helpers(entity, state)
  return state
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
  ensure_lua_helpers(entity, state)
  return state
end

function selector_mode.set_stack_pack(entity)
  local state = enter_script_mode(entity, selector_mode.MODE_STACK_PACK)
  if state.slots == nil then
    state.slots = 48
  end
  if state.select_max == nil then
    state.select_max = true
  end
  ensure_lua_helpers(entity, state)
  return state
end

--- Stack Pack: set the slot budget X from the GUI constant field.
function selector_mode.set_pack_slots(entity, slots)
  local state = mode_states()[entity.unit_number]
  if state then
    state.slots = slots
    selector_mode.dirty(entity.unit_number)
  end
end

--- Stack Pack: read the slot budget X from a chosen input signal (nil = use
--- the constant). The chosen signal is excluded from packing at compute time.
function selector_mode.set_pack_slots_signal(entity, signal)
  local state = mode_states()[entity.unit_number]
  if state then
    state.slots_signal = signal
    selector_mode.dirty(entity.unit_number)
  end
end

--- Stack Pack: order items by count descending (max) or ascending.
function selector_mode.set_pack_sort(entity, select_max)
  local state = mode_states()[entity.unit_number]
  if state then
    state.select_max = select_max
    selector_mode.dirty(entity.unit_number)
  end
end

function selector_mode.set_memory_cell(entity)
  local state, changed = enter_script_mode(entity, selector_mode.MODE_MEMORY_CELL)
  if changed then
    state.stored = {}
  end
  state.condition = state.condition or { comparator = "<", constant = 0 }
  ensure_lua_helpers(entity, state)
  return state
end

--- Mark a script combinator dirty so it recomputes even with an unchanged
--- input frame. Crafting-Time rewrites its engine map; Lua Modes flag their
--- group forced and clear the cached output.
function selector_mode.dirty(unit_number)
  local state = mode_states()[unit_number]
  if not state then
    return
  end
  if state.mode == selector_mode.MODE_CRAFTING_TIME then
    write_ct_map(state)
    return
  end
  state.last_output = nil
  state.dirty = true
  local g = state.group_id and storage.sc_groups and storage.sc_groups[state.group_id]
  if g then
    g.forced = true
  end
end

--- Update a Recipe Finder Filter and force a recompute.
function selector_mode.set_filter(entity, filter, value)
  local state = mode_states()[entity.unit_number]
  if state then
    state[filter] = value
    selector_mode.dirty(entity.unit_number)
  end
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
  destroy_helpers(state, entity.unit_number)
  entity.disabled_by_script = false
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
    selector_mode.dirty(entity.unit_number)
  end
end

function selector_mode.set_machine(entity, machine_name)
  local state = mode_states()[entity.unit_number]
  if state then
    state.machine = machine_name
    selector_mode.dirty(entity.unit_number)
  end
end

function selector_mode.forget(unit_number)
  local state = mode_states()[unit_number]
  if state then
    destroy_helpers(state, unit_number)
    local entity = state.entity
    if entity and entity.valid then
      entity.disabled_by_script = false
    end
    mode_states()[unit_number] = nil
  end
end

--- Drop the force's cached researched set and mark the force's Recipe
--- Finders dirty so they recompute even with an unchanged input frame.
function selector_mode.on_research_changed(event)
  local force = event.research.force
  researched_cache[force.index] = nil
  for un, state in pairs(mode_states()) do
    if state.mode == selector_mode.MODE_RECIPE_FINDER then
      local entity = state.entity
      if entity and entity.valid and entity.force.index == force.index then
        selector_mode.dirty(un)
      end
    end
  end
end

-- Rebuild every script Mode's helpers from scratch (groups, sentinels, engine
-- chains). Run on configuration changes: migrates pre-engine / pre-group
-- saves and recovers from any helper drift.
function selector_mode.migrate()
  if storage.sc_groups then
    for _, g in pairs(storage.sc_groups) do
      if g.anchor and g.anchor.valid then
        g.anchor.destroy()
      end
    end
  end
  storage.sc_groups = {}
  storage.sc_group_seq = 0
  anchor_reads = {}
  sentinel_reads = {}
  for un, state in pairs(mode_states()) do
    local entity = state.entity
    if entity and entity.valid then
      entity.disabled_by_script = true
      state.group_id = nil
      state.last_output = nil
      state.last_input = nil
      state.sentinel_value = nil
      state.dirty = nil
      -- Drop whatever helpers the old save had; rebuild for this Mode.
      for _, field in ipairs({ "output", "sentinel", "merge", "map", "gate" }) do
        local helper = state[field]
        if helper and helper.valid then
          helper.destroy()
        end
        state[field] = nil
      end
      if state.mode == selector_mode.MODE_CRAFTING_TIME then
        ensure_ct_helpers(entity, state)
        write_ct_map(state)
      else
        ensure_lua_helpers(entity, state)
      end
    else
      mode_states()[un] = nil
    end
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
    -- A request (non-zero min) needs a concrete quality on EVERY signal type;
    -- a quality-less value is the "non trivial item filter condition" the
    -- engine refuses to pair with a request. Pin quality (+ "=") for all
    -- symbols, not just items — virtual/fluid/recipe alike.
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

-- Scalar value of one signal id in an engine signal array, 0 when absent.
-- Only runs on change ticks (when Stack Pack reads X from a signal).
local function signal_value(signals, id)
  local want_type = id.type or "item"
  local want_quality = id.quality or "normal"
  for i = 1, #signals do
    local sid = signals[i].signal
    if
      sid.name == id.name
      and (sid.type or "item") == want_type
      and (sid.quality or "normal") == want_quality
    then
      return signals[i].count
    end
  end
  return 0
end

local function compute_stack_pack(state, signals)
  local x = state.slots or 0
  if state.slots_signal then
    x = signal_value(signals, state.slots_signal)
  end
  return stack_pack.map(
    to_frame(signals),
    stack_sizes(),
    x,
    state.select_max ~= false,
    state.slots_signal
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
  [selector_mode.MODE_MEMORY_CELL] = compute_memory_cell,
  [selector_mode.MODE_RECIPE_PRODUCTS] = compute_recipe_products,
  [selector_mode.MODE_RECIPE_FINDER] = compute_recipe_finder,
  [selector_mode.MODE_STACK_PACK] = compute_stack_pack,
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
  local all = storage.sc_groups
  if not all or next(all) == nil then
    return
  end
  local states = storage.sc_modes
  local tick = game.tick
  for gid, group in pairs(all) do
    local anchor = group.anchor
    local anchor_valid = anchor and anchor.valid
    local sweep_due = (tick + gid) % SWEEP_INTERVAL == 0
    local sum
    if anchor_valid then
      local read = anchor_reads[gid]
      if not read then
        read = anchor.get_or_create_control_behavior().get_signal_last_tick
        anchor_reads[gid] = read
      end
      sum = read(SENTINEL_SIGNAL) or 0
    end
    if group.forced or sweep_due or not anchor_valid or sum ~= group.last_sum then
      group.last_sum = sum
      group.forced = false
      for un in pairs(group.members) do
        local state = states[un]
        if not state then
          group.members[un] = nil
          group.count = group.count - 1
        else
          local entity = state.entity
          if not (entity and entity.valid) then
            selector_mode.forget(un)
          else
            local sentinel = state.sentinel
            if not (sentinel and sentinel.valid) then
              ensure_sentinel(entity, state)
              if anchor_valid then
                connect(state.sentinel, OUT_RED, anchor, IN_RED)
              end
              drive(entity, state, COMPUTE[state.mode])
            else
              local mread = sentinel_reads[un]
              if not mread then
                mread = sentinel.get_or_create_control_behavior().get_signal_last_tick
                sentinel_reads[un] = mread
              end
              local value = mread(SENTINEL_SIGNAL) or 0
              if state.dirty or sweep_due or value ~= state.sentinel_value then
                state.sentinel_value = value
                state.dirty = nil
                drive(entity, state, COMPUTE[state.mode])
              end
            end
          end
        end
      end
    end
  end
end

return selector_mode
