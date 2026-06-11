-- Persistence of mod settings through the build workflow: blueprints,
-- ghost revival, copy-paste, cloning, undo/redo. Configuration travels as
-- one "lca" tag (Mode, Target Machine, Filters, Update Condition, plus the
-- stashed vanilla settings); live state like the Stored Frame never does.
-- Vanilla-Mode combinators get no tag at all.

local preset = require("runtime.preset")
local selector_mode = require("runtime.selector_mode")

local persist = {}

local OUTPUT_ENTITY = "lca-hidden-output"

-- Deep copy for plain config tables (drops userdata, which tags reject).
local function copy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for k, v in pairs(value) do
    if type(v) ~= "userdata" then
      out[k] = copy(v)
    end
  end
  return out
end

-- The "lca" tag payload for an entity, nil when it blueprints as unmodded.
local function tag_for(entity)
  if entity.type == "constant-combinator" then
    local state = storage.cc_modes and storage.cc_modes[entity.unit_number]
    if state and state.mode == preset.MODE_CRAFTABLE_SET then
      return {
        mode = state.mode,
        machine = state.machine,
        researched_only = state.researched_only ~= false,
        no_fluid = state.no_fluid == true,
        stash = copy(state.stash),
      }
    end
  elseif entity.type == "selector-combinator" then
    local state = storage.sc_modes and storage.sc_modes[entity.unit_number]
    if state and state.mode == selector_mode.MODE_CRAFTING_TIME then
      return { mode = state.mode, machine = state.machine, stash = copy(state.stash) }
    end
    if state and state.mode == selector_mode.MODE_MEMORY_CELL then
      return { mode = state.mode, condition = copy(state.condition), stash = copy(state.stash) }
    end
    if state and state.mode == selector_mode.MODE_RECIPE_PRODUCTS then
      return { mode = state.mode, stash = copy(state.stash) }
    end
    if state and state.mode == selector_mode.MODE_RECIPE_FINDER then
      return {
        mode = state.mode,
        machine = state.machine,
        researched_only = state.researched_only ~= false,
        no_fluid = state.no_fluid == true,
        stash = copy(state.stash),
      }
    end
  end
  return nil
end

-- Reconfigure a placed entity from a tag payload. A Preset recomputes for
-- the entity's force; a Memory Cell starts with an empty Stored Frame.
local function apply_tag(entity, tag)
  if type(tag) ~= "table" then
    return
  end
  if entity.type == "constant-combinator" and tag.mode == preset.MODE_CRAFTABLE_SET then
    local state = preset.state_for(entity)
    state.machine = tag.machine
    state.researched_only = tag.researched_only ~= false
    state.no_fluid = tag.no_fluid == true
    if state.mode ~= preset.MODE_CRAFTABLE_SET then
      preset.set_mode(entity, preset.MODE_CRAFTABLE_SET)
    else
      preset.apply(entity, state)
    end
    state.stash = copy(tag.stash)
  elseif entity.type == "selector-combinator" then
    if tag.mode == selector_mode.MODE_CRAFTING_TIME then
      local state = selector_mode.set_crafting_time(entity)
      state.machine = tag.machine
      state.last_output = nil
      if tag.stash then
        state.stash = copy(tag.stash)
      end
    elseif tag.mode == selector_mode.MODE_MEMORY_CELL then
      local state = selector_mode.set_memory_cell(entity)
      state.condition = copy(tag.condition) or state.condition
      state.stored = {}
      state.last_output = nil
      if tag.stash then
        state.stash = copy(tag.stash)
      end
    elseif tag.mode == selector_mode.MODE_RECIPE_PRODUCTS then
      local state = selector_mode.set_recipe_products(entity)
      state.last_output = nil
      if tag.stash then
        state.stash = copy(tag.stash)
      end
    elseif tag.mode == selector_mode.MODE_RECIPE_FINDER then
      local state = selector_mode.set_recipe_finder(entity)
      state.machine = tag.machine
      state.researched_only = tag.researched_only ~= false
      state.no_fluid = tag.no_fluid == true
      state.last_output = nil
      if tag.stash then
        state.stash = copy(tag.stash)
      end
    end
  end
end

-- Blueprint capture: write the tag onto each mapped modded combinator.
function persist.on_setup_blueprint(event)
  local mapping = event.mapping and event.mapping.get()
  if not mapping then
    return
  end
  -- The blueprint being set up: an item in hand, or a library record.
  local target = event.stack
  if not (target and target.valid_for_read) then
    target = event.record
  end
  if not target then
    return
  end
  for index, entity in pairs(mapping) do
    if entity and entity.valid then
      local tag = tag_for(entity)
      if tag then
        local ok, err = pcall(function()
          target.set_blueprint_entity_tag(index, "lca", tag)
        end)
        if not ok then
          log(err)
        end
      end
    end
  end
end

-- Ghost revival and other builds; event.tags carries the blueprint tags.
function persist.on_built(event)
  local entity = event.entity
  if not (entity and entity.valid) then
    return
  end
  local tag = event.tags and event.tags.lca
  if tag then
    apply_tag(entity, tag)
  end
end

-- Engine has already pasted the vanilla settings (sections/parameters)
-- when this fires; mod state follows the source's lead.
function persist.on_settings_pasted(event)
  local source, dest = event.source, event.destination
  if not (source and source.valid and dest and dest.valid) then
    return
  end
  if source.type ~= dest.type then
    return
  end
  local tag = tag_for(source)
  if tag then
    apply_tag(dest, tag)
  elseif dest.type == "constant-combinator" then
    -- Source is vanilla: the pasted sections are the wanted ones.
    preset.forget(dest.unit_number)
  elseif dest.type == "selector-combinator" then
    -- Source is vanilla: keep the pasted parameters, drop the script Mode.
    selector_mode.forget(dest.unit_number)
  end
end

function persist.on_cloned(event)
  local source, dest = event.source, event.destination
  if not (dest and dest.valid) then
    return
  end
  if dest.name == OUTPUT_ENTITY then
    -- Area clones duplicate the hidden output; the owning selector
    -- recreates its own, so the stray copy goes.
    dest.destroy()
    return
  end
  if source and source.valid then
    local tag = tag_for(source)
    if tag then
      apply_tag(dest, tag)
    end
  end
end

-- Attach the tag to the matching removed-entity action on top of the
-- player's undo stack. Returns true when attached.
local function attach_undo_tag(player, name, position, tag)
  local ok, attached = pcall(function()
    local stack = player.undo_redo_stack
    if stack.get_undo_item_count() == 0 then
      return false
    end
    local item = stack.get_undo_item(1)
    for i, action in ipairs(item) do
      if
        action.type == "removed-entity"
        and action.target
        and action.target.name == name
        and action.target.position.x == position.x
        and action.target.position.y == position.y
      then
        stack.set_undo_tag(1, i, "lca", tag)
        return true
      end
    end
    return false
  end)
  return ok and attached
end

local function remember_for_undo(event)
  local entity = event.entity
  if not (entity and entity.valid and event.player_index) then
    return
  end
  local tag = tag_for(entity)
  if not tag then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  if not attach_undo_tag(player, entity.name, entity.position, tag) then
    -- The undo item may not exist yet; retry once next tick.
    storage.lca_pending_undo = storage.lca_pending_undo or {}
    local pending = storage.lca_pending_undo
    pending[#pending + 1] = {
      player_index = event.player_index,
      name = entity.name,
      position = { x = entity.position.x, y = entity.position.y },
      tag = tag,
    }
  end
end

persist.on_player_mined = remember_for_undo
persist.on_marked_for_deconstruction = remember_for_undo

function persist.on_tick()
  local pending = storage.lca_pending_undo
  if not pending or #pending == 0 then
    return
  end
  for _, entry in ipairs(pending) do
    local player = game.get_player(entry.player_index)
    if player then
      attach_undo_tag(player, entry.name, entry.position, entry.tag)
    end
  end
  storage.lca_pending_undo = nil
end

-- Undo/redo re-placed something with our tag: usually a ghost (configure
-- it for revival), in instant-build contexts the entity itself.
function persist.on_undo_applied(event)
  for _, action in pairs(event.actions or {}) do
    local tag = action.tags and action.tags.lca
    if tag and action.target then
      local surface = game.surfaces[action.surface_index]
      if surface then
        local position = action.target.position
        for _, ghost in pairs(surface.find_entities_filtered{
          name = "entity-ghost",
          position = position,
          radius = 0.2,
        }) do
          if ghost.ghost_name == action.target.name then
            local tags = ghost.tags or {}
            tags.lca = tag
            ghost.tags = tags
          end
        end
        for _, entity in pairs(surface.find_entities_filtered{
          name = action.target.name,
          position = position,
          radius = 0.2,
        }) do
          apply_tag(entity, tag)
        end
      end
    end
  end
end

return persist
