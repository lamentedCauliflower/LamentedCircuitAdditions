-- Pure domain logic: Recipe Finder Mode and the Primary Recipe tie-break
-- (see CONTEXT.md, ADR-0002).
-- Modules under domain/ must not touch the Factorio API so they stay loadable
-- from the busted test suite outside the game.
local recipe_finder = {}

local function product_key(type, name)
  return type .. "/" .. name
end

--- Producer index: product (type, name) -> candidate recipes sorted by name.
--- Built once per recipe set; hidden and parameter recipes never qualify as
--- producers, so they are excluded here.
--- @param recipes table[] plain recipe data:
---   { name, category, hidden, parameter, has_fluid_ingredient,
---     products = { { type, name }, ... }, main_product = { type, name }? }
--- @return table<string, table[]> candidates:
---   { name, category, has_fluid_ingredient, is_main }
function recipe_finder.index(recipes)
  local index = {}
  for _, recipe in ipairs(recipes) do
    if not recipe.hidden and not recipe.parameter then
      for _, product in ipairs(recipe.products or {}) do
        local key = product_key(product.type, product.name)
        local main = recipe.main_product
        local candidates = index[key]
        if not candidates then
          candidates = {}
          index[key] = candidates
        end
        candidates[#candidates + 1] = {
          name = recipe.name,
          category = recipe.category,
          has_fluid_ingredient = recipe.has_fluid_ingredient,
          is_main = main ~= nil and main.type == product.type and main.name == product.name,
        }
      end
    end
  end
  for _, candidates in pairs(index) do
    table.sort(candidates, function(a, b)
      return a.name < b.name
    end)
  end
  return index
end

--- The Primary Recipe among a product's candidates on a machine: the recipe
--- named exactly like the product, else the alphabetically first whose main
--- product it is, else the alphabetically first qualifying producer.
local function primary(candidates, product_name, machine_categories)
  local first_main, first_any
  for _, candidate in ipairs(candidates) do
    if machine_categories[candidate.category] then
      if candidate.name == product_name then
        return candidate.name
      end
      if candidate.is_main and not first_main then
        first_main = candidate.name
      end
      if not first_any then
        first_any = candidate.name
      end
    end
  end
  return first_main or first_any
end

--- Map a combined input frame to Primary Recipe signals on a Target Machine.
--- Non-item/fluid signals, zero counts and inputs with no qualifying
--- producer are dropped. The input value passes through and the input
--- quality is inherited; inputs resolving to the same recipe at the same
--- quality sum their values.
--- @param frame table[] combined input signals: { type, name, quality, count }
--- @param index table producer index from recipe_finder.index
--- @param machine_categories table<string, boolean> the machine's crafting categories
--- @return table[] recipe signals sorted by name then quality:
---   { type = "recipe", name, quality, count }
function recipe_finder.find(frame, index, machine_categories)
  local merged, out = {}, {}
  for _, signal in ipairs(frame) do
    if (signal.type == "item" or signal.type == "fluid") and signal.count ~= 0 then
      local candidates = index[product_key(signal.type, signal.name)]
      local recipe = candidates and primary(candidates, signal.name, machine_categories)
      if recipe then
        local quality = signal.quality or "normal"
        local key = recipe .. "/" .. quality
        local entry = merged[key]
        if entry then
          entry.count = entry.count + signal.count
        else
          entry = { type = "recipe", name = recipe, quality = quality, count = signal.count }
          merged[key] = entry
          out[#out + 1] = entry
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.quality < b.quality
  end)
  return out
end

return recipe_finder
