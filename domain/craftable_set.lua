-- Pure domain logic: the Craftable Set (see CONTEXT.md).
-- Modules under domain/ must not touch the Factorio API so they stay loadable
-- from the busted test suite outside the game.
local craftable_set = {}

--- Recipes a Target Machine can craft, after Filters.
--- @param recipes table[] plain recipe data:
---   { name, categories, hidden, parameter, has_fluid_ingredient }
--- @param machine_categories table<string, boolean> the machine's crafting categories
--- @param filters table { researched_only = boolean, no_fluid_inputs = boolean }
--- @param researched table<string, boolean> recipe names enabled for the force
--- @return string[] sorted recipe names
function craftable_set.compute(recipes, machine_categories, filters, researched)
  local names = {}
  for _, recipe in ipairs(recipes) do
    local craftable = false
    for _, category in ipairs(recipe.categories or {}) do
      if machine_categories[category] then
        craftable = true
        break
      end
    end
    if
      craftable
      and not recipe.hidden
      and not recipe.parameter
      and (not filters.researched_only or researched[recipe.name])
      and (not filters.no_fluid_inputs or not recipe.has_fluid_ingredient)
    then
      names[#names + 1] = recipe.name
    end
  end
  table.sort(names)
  return names
end

return craftable_set
