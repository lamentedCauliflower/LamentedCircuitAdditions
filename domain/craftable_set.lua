-- Pure domain logic: the Craftable Set (see CONTEXT.md).
-- Modules under domain/ must not touch the Factorio API so they stay loadable
-- from the busted test suite outside the game.
local craftable_set = {}

--- Recipes a Target Machine can craft, after Filters, as signals.
--- A recipe with an item main product is emitted as that item's signal;
--- recipes without one (fluid or multi-output) fall back to the recipe
--- signal. Duplicates (several recipes making the same item) collapse.
--- @param recipes table[] plain recipe data:
---   { name, category, hidden, parameter, has_fluid_ingredient, item_product }
--- @param machine_categories table<string, boolean> the machine's crafting categories
--- @param filters table { researched_only = boolean, no_fluid_inputs = boolean }
--- @param researched table<string, boolean> recipe names enabled for the force
--- @return table[] sorted, deduplicated { type = "item"|"recipe", name = string }
function craftable_set.compute(recipes, machine_categories, filters, researched)
  local signals, seen = {}, {}
  for _, recipe in ipairs(recipes) do
    if
      machine_categories[recipe.category]
      and not recipe.hidden
      and not recipe.parameter
      and (not filters.researched_only or researched[recipe.name])
      and (not filters.no_fluid_inputs or not recipe.has_fluid_ingredient)
    then
      local signal
      if recipe.item_product then
        signal = { type = "item", name = recipe.item_product }
      else
        signal = { type = "recipe", name = recipe.name }
      end
      local key = signal.type .. "/" .. signal.name
      if not seen[key] then
        seen[key] = true
        signals[#signals + 1] = signal
      end
    end
  end
  table.sort(signals, function(a, b)
    if a.type ~= b.type then
      return a.type < b.type
    end
    return a.name < b.name
  end)
  return signals
end

return craftable_set
