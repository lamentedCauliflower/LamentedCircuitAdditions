-- Preset Mode for the constant combinator: adapts game prototypes and force
-- state to the pure Craftable Set computation, and manages the entity's
-- logistic sections when switching Modes (exclusive, non-destructive).

local craftable_set = require("domain.craftable_set")

local preset = {}

preset.MODE_LOGISTIC_GROUPS = "logistic-groups"
preset.MODE_CRAFTABLE_SET = "craftable-set"

local function mode_states()
  storage.cc_modes = storage.cc_modes or {}
  return storage.cc_modes
end

-- Shared with the selector Modes as the initial Target Machine.
function preset.default_machine()
  if prototypes.entity["assembling-machine-1"] then
    return "assembling-machine-1"
  end
  for name, proto in pairs(prototypes.entity) do
    if next(proto.crafting_categories or {}) then
      return name
    end
  end
  return nil
end

--- Per-combinator mod state, created on first access. Keeps an entity
--- reference so research events can recompute without a GUI open.
function preset.state_for(entity)
  local all = mode_states()
  local state = all[entity.unit_number]
  if not state then
    state = { mode = preset.MODE_LOGISTIC_GROUPS }
    all[entity.unit_number] = state
  end
  state.entity = entity
  return state
end

function preset.forget(unit_number)
  mode_states()[unit_number] = nil
end

-- Plain-data views of game state for the domain module.

local function recipe_data()
  local list = {}
  for name, proto in pairs(prototypes.recipe) do
    local has_fluid = false
    for _, ingredient in pairs(proto.ingredients or {}) do
      if ingredient.type == "fluid" then
        has_fluid = true
        break
      end
    end
    list[#list + 1] = {
      name = name,
      category = proto.category,
      hidden = proto.hidden,
      parameter = proto.parameter,
      has_fluid_ingredient = has_fluid,
    }
  end
  return list
end

local function researched_set(force)
  local set = {}
  for name, recipe in pairs(force.recipes) do
    if recipe.enabled then
      set[name] = true
    end
  end
  return set
end

--- The Craftable Set for a config, as sorted recipe names.
function preset.compute(force, state)
  local machine = state.machine and prototypes.entity[state.machine]
  if not machine then
    return {}
  end
  return craftable_set.compute(
    recipe_data(),
    machine.crafting_categories or {},
    {
      researched_only = state.researched_only ~= false,
      no_fluid_inputs = state.no_fluid == true,
    },
    researched_set(force)
  )
end

-- Section stash/restore for non-destructive Mode switching.

local function clear_sections(cb)
  while cb.sections_count > 0 do
    cb.remove_section(1)
  end
end

function preset.stash_sections(cb)
  local stash = {}
  for _, section in ipairs(cb.sections) do
    local entry = {
      group = section.group,
      active = section.active,
      multiplier = section.multiplier,
    }
    if section.group == "" then
      entry.filters = section.filters
    end
    stash[#stash + 1] = entry
  end
  return stash
end

function preset.restore_sections(cb, stash)
  clear_sections(cb)
  for _, entry in ipairs(stash or {}) do
    local section = entry.group ~= "" and cb.add_section(entry.group) or cb.add_section()
    if entry.group == "" and entry.filters then
      section.filters = entry.filters
    end
    section.active = entry.active
    section.multiplier = entry.multiplier
  end
  if cb.sections_count == 0 then
    cb.add_section()
  end
end

local function to_filters(names)
  local out = {}
  for i, name in ipairs(names) do
    -- min = 1 is a request, so the value must pin a concrete quality (+ "=");
    -- a quality-less filter is the non-trivial condition the engine rejects.
    out[i] = {
      value = { type = "recipe", name = name, quality = "normal", comparator = "=" },
      min = 1,
    }
  end
  return out
end

--- Recompute and write the Craftable Set into the combinator's single
--- mod-managed section. Returns the number of recipe signals written.
function preset.apply(entity, state)
  local cb = entity.get_or_create_control_behavior()
  local names = preset.compute(entity.force, state)
  clear_sections(cb)
  local section = cb.add_section()
  section.filters = to_filters(names)
  script.register_on_object_destroyed(entity)
  return #names
end

-- States saved before entity references were kept (or after surface
-- surgery) get relinked by scanning for constant combinators once.
local function rebind_entities()
  local by_unit = mode_states()
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered{ type = "constant-combinator" }) do
      local state = by_unit[entity.unit_number]
      if state and not (state.entity and state.entity.valid) then
        state.entity = entity
      end
    end
  end
end

--- Recompute every researched-only Craftable Set combinator of the force
--- whose research changed. Fired on research finished and reversed.
function preset.on_research_changed(event)
  local force = event.research.force
  local needs_rebind = false
  for _, state in pairs(mode_states()) do
    if state.mode == preset.MODE_CRAFTABLE_SET and not (state.entity and state.entity.valid) then
      needs_rebind = true
      break
    end
  end
  if needs_rebind then
    rebind_entities()
  end
  for _, state in pairs(mode_states()) do
    local entity = state.entity
    if
      state.mode == preset.MODE_CRAFTABLE_SET
      and state.researched_only ~= false
      and entity
      and entity.valid
      and entity.force == force
    then
      preset.apply(entity, state)
    end
  end
end

--- Switch a combinator between Modes. No-op when already in that Mode.
function preset.set_mode(entity, mode)
  local state = preset.state_for(entity)
  if state.mode == mode then
    return state
  end
  local cb = entity.get_or_create_control_behavior()
  if mode == preset.MODE_CRAFTABLE_SET then
    state.stash = preset.stash_sections(cb)
    state.mode = mode
    if state.machine == nil then
      state.machine = preset.default_machine()
    end
    if state.researched_only == nil then
      state.researched_only = true
    end
    if state.no_fluid == nil then
      state.no_fluid = false
    end
    preset.apply(entity, state)
  else
    state.mode = preset.MODE_LOGISTIC_GROUPS
    preset.restore_sections(cb, state.stash)
    state.stash = nil
  end
  return state
end

return preset
