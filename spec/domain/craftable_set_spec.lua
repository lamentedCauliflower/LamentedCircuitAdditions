local craftable_set = require("domain.craftable_set")

local function recipe(name, overrides)
  local r = {
    name = name,
    category = "crafting",
    hidden = false,
    parameter = false,
    has_fluid_ingredient = false,
  }
  for k, v in pairs(overrides or {}) do
    r[k] = v
  end
  return r
end

local CATEGORIES = { crafting = true, ["crafting-with-fluid"] = true }
local NO_FILTERS = { researched_only = false, no_fluid_inputs = false }

describe("domain.craftable_set.compute", function()
  it("includes recipes whose category the machine crafts, sorted", function()
    local result = craftable_set.compute(
      { recipe("iron-gear-wheel"), recipe("copper-cable") },
      CATEGORIES, NO_FILTERS, {}
    )
    assert.are.same({ "copper-cable", "iron-gear-wheel" }, result)
  end)

  it("excludes recipes of categories the machine lacks", function()
    local result = craftable_set.compute(
      { recipe("steel-plate", { category = "smelting" }), recipe("iron-gear-wheel") },
      CATEGORIES, NO_FILTERS, {}
    )
    assert.are.same({ "iron-gear-wheel" }, result)
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
    assert.are.same({ "iron-gear-wheel" }, result)
  end)

  it("excludes unresearched recipes when researched_only is on", function()
    local recipes = { recipe("iron-gear-wheel"), recipe("rocket-fuel") }
    local researched = { ["iron-gear-wheel"] = true }
    local on = craftable_set.compute(recipes, CATEGORIES,
      { researched_only = true, no_fluid_inputs = false }, researched)
    local off = craftable_set.compute(recipes, CATEGORIES, NO_FILTERS, researched)
    assert.are.same({ "iron-gear-wheel" }, on)
    assert.are.same({ "iron-gear-wheel", "rocket-fuel" }, off)
  end)

  it("excludes fluid-ingredient recipes when no_fluid_inputs is on", function()
    local recipes = {
      recipe("iron-gear-wheel"),
      recipe("processing-unit", { category = "crafting-with-fluid", has_fluid_ingredient = true }),
    }
    local on = craftable_set.compute(recipes, CATEGORIES,
      { researched_only = false, no_fluid_inputs = true }, {})
    local off = craftable_set.compute(recipes, CATEGORIES, NO_FILTERS, {})
    assert.are.same({ "iron-gear-wheel" }, on)
    assert.are.same({ "iron-gear-wheel", "processing-unit" }, off)
  end)
end)
