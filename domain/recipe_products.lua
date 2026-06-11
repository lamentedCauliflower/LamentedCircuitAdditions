-- Pure domain logic: Recipe Products Mode mapping (see CONTEXT.md).
-- Modules under domain/ must not touch the Factorio API so they stay loadable
-- from the busted test suite outside the game.
local recipe_products = {}

--- Nominal per-craft amount of one product: the fixed amount, or the rounded
--- average of an amount range. Probability is deliberately ignored so rare
--- products (e.g. U-235) never round away to nothing.
local function nominal_amount(product)
  if product.amount then
    return product.amount
  end
  return math.floor((product.amount_min + product.amount_max) / 2 + 0.5)
end

--- Map a combined input frame to the products of its recipe signals.
--- Input values are ignored (any nonzero count is a presence flag);
--- non-recipe signals and unknown recipes are dropped. A product shared by
--- several input recipes appears once with its nominal amounts summed.
--- @param frame table[] combined input signals: { type, name, quality, count }
--- @param products_by_recipe table<string, table[]> recipe name -> products:
---   { type = "item"|"fluid", name, amount? , amount_min?, amount_max? }
--- @return table[] product signals sorted by type then name:
---   { type, name, quality = "normal", count = nominal amount }
function recipe_products.map(frame, products_by_recipe)
  local merged, out = {}, {}
  for _, signal in ipairs(frame) do
    if signal.type == "recipe" and signal.count ~= 0 then
      for _, product in ipairs(products_by_recipe[signal.name] or {}) do
        local key = product.type .. "/" .. product.name
        local entry = merged[key]
        if entry then
          entry.count = entry.count + nominal_amount(product)
        else
          entry = {
            type = product.type,
            name = product.name,
            quality = "normal",
            count = nominal_amount(product),
          }
          merged[key] = entry
          out[#out + 1] = entry
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.type ~= b.type then
      return a.type < b.type
    end
    return a.name < b.name
  end)
  return out
end

return recipe_products
