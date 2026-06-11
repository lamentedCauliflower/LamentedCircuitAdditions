local craftable_set = require("domain.craftable_set")

local function recipe(name, overrides)
  local r = {
    name = name,
    category = "crafting",
    hidden = false,
    parameter = false,
    has_fluid_ingredient = false,
    item_product = nil,
  }
  for k, v in pairs(overrides or {}) do
    r[k] = v
  end
  return r
end

local function item(name)
  return { type = "item", name = name }
end

local function recipe_signal(name)
  return { type = "recipe", name = name }
end

local CATEGORIES = { crafting = true, ["crafting-with-fluid"] = true }
local NO_FILTERS = { researched_only = false, no_fluid_inputs = false }

describe("domain.craftable_set.compute", function()
  it("includes recipes whose category the machine crafts, sorted", function()
    local result = craftable_set.compute(
      { recipe("iron-gear-wheel"), recipe("copper-cable") },
      CATEGORIES, NO_FILTERS, {}
    )
    assert.are.same({ recipe_signal("copper-cable"), recipe_signal("iron-gear-wheel") }, result)
  end)

  it("emits the item signal when a recipe has an item main product", function()
    local result = craftable_set.compute(
      {
        recipe("fill-water-barrel", { item_product = "water-barrel" }),
        recipe("lubricant", { item_product = nil }),
      },
      CATEGORIES, NO_FILTERS, {}
    )
    assert.are.same({ item("water-barrel"), recipe_signal("lubricant") }, result)
  end)

  it("collapses recipes sharing the same item product", function()
    local result = craftable_set.compute(
      {
        recipe("solid-fuel-from-light-oil", { item_product = "solid-fuel" }),
        recipe("solid-fuel-from-petroleum", { item_product = "solid-fuel" }),
      },
      CATEGORIES, NO_FILTERS, {}
    )
    assert.are.same({ item("solid-fuel") }, result)
  end)

  it("excludes recipes of categories the machine lacks", function()
    local result = craftable_set.compute(
      { recipe("steel-plate", { category = "smelting" }), recipe("iron-gear-wheel") },
      CATEGORIES, NO_FILTERS, {}
    )
    assert.are.same({ recipe_signal("iron-gear-wheel") }, result)
  end)

  it("always excludes hidden and parameter recipes", function()
    local result = craftable_set.compute(
      {
        recipe("iron-gear-wheel"),
        recipe("secret", { hidden = true }),
        recipe("parameter-0", { parameter = true }),
      },
      CATEGORIES, NO_FILTERS, {}
    )
    assert.are.same({ recipe_signal("iron-gear-wheel") }, result)
  end)

  it("excludes unresearched recipes when researched_only is on", function()
    local recipes = { recipe("iron-gear-wheel"), recipe("rocket-fuel") }
    local researched = { ["iron-gear-wheel"] = true }
    local on = craftable_set.compute(recipes, CATEGORIES,
      { researched_only = true, no_fluid_inputs = false }, researched)
    local off = craftable_set.compute(recipes, CATEGORIES, NO_FILTERS, researched)
    assert.are.same({ recipe_signal("iron-gear-wheel") }, on)
    assert.are.same({ recipe_signal("iron-gear-wheel"), recipe_signal("rocket-fuel") }, off)
  end)

  it("tracks researched-set changes on recompute", function()
    local recipes = { recipe("iron-gear-wheel"), recipe("engine-unit") }
    local filters = { researched_only = true, no_fluid_inputs = false }
    local before = craftable_set.compute(recipes, CATEGORIES, filters,
      { ["iron-gear-wheel"] = true })
    local after = craftable_set.compute(recipes, CATEGORIES, filters,
      { ["iron-gear-wheel"] = true, ["engine-unit"] = true })
    local reversed = craftable_set.compute(recipes, CATEGORIES, filters,
      { ["engine-unit"] = true })
    assert.are.same({ recipe_signal("iron-gear-wheel") }, before)
    assert.are.same({ recipe_signal("engine-unit"), recipe_signal("iron-gear-wheel") }, after)
    assert.are.same({ recipe_signal("engine-unit") }, reversed)
  end)

  it("excludes fluid-ingredient recipes when no_fluid_inputs is on", function()
    local recipes = {
      recipe("iron-gear-wheel"),
      recipe("processing-unit", { category = "crafting-with-fluid", has_fluid_ingredient = true }),
    }
    local on = craftable_set.compute(recipes, CATEGORIES,
      { researched_only = false, no_fluid_inputs = true }, {})
    local off = craftable_set.compute(recipes, CATEGORIES, NO_FILTERS, {})
    assert.are.same({ recipe_signal("iron-gear-wheel") }, on)
    assert.are.same({ recipe_signal("iron-gear-wheel"), recipe_signal("processing-unit") }, off)
  end)
end)
