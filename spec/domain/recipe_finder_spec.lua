local recipe_finder = require("domain.recipe_finder")

local function sig(type, name, count, quality)
  return { type = type, name = name, quality = quality or "normal", count = count }
end

local function recipe(name, products, overrides)
  local r = {
    name = name,
    categories = { "crafting" },
    hidden = false,
    parameter = false,
    has_fluid_ingredient = false,
    products = products,
  }
  for k, v in pairs(overrides or {}) do
    r[k] = v
  end
  return r
end

local function item(name)
  return { type = "item", name = name }
end

local function fluid(name)
  return { type = "fluid", name = name }
end

local CRAFTING = { crafting = true }
local NO_FILTERS = { researched_only = false, no_fluid_inputs = false }

local function find(frame, recipes, categories, filters, researched)
  return recipe_finder.find(
    frame,
    recipe_finder.index(recipes),
    categories or CRAFTING,
    filters or NO_FILTERS,
    researched or {}
  )
end

describe("domain.recipe_finder.find", function()
  it("maps an item to the recipe producing it, passing the value through", function()
    local out = find(
      { sig("item", "iron-gear-wheel", 50) },
      { recipe("iron-gear-wheel", { item("iron-gear-wheel") }) }
    )
    assert.are.same({
      { type = "recipe", name = "iron-gear-wheel", quality = "normal", count = 50 },
    }, out)
  end)

  it("maps a fluid to the recipe producing it", function()
    local out = find(
      { sig("fluid", "sulfuric-acid", 7) },
      { recipe("sulfuric-acid", { fluid("sulfuric-acid") }) }
    )
    assert.are.same({
      { type = "recipe", name = "sulfuric-acid", quality = "normal", count = 7 },
    }, out)
  end)

  describe("Primary Recipe tie-break", function()
    local producers = {
      recipe("aaa-byproduct", { item("widget"), item("scrap") }),
      recipe("widget-pressing", { item("widget") }, { main_product = item("widget") }),
      recipe("widget", { item("widget") }),
    }

    it("prefers the recipe named exactly like the product", function()
      local out = find({ sig("item", "widget", 1) }, producers)
      assert.are.equal("widget", out[1].name)
    end)

    it("falls back to the alphabetically first main-product match", function()
      local without_name_match = { producers[1], producers[2] }
      local out = find({ sig("item", "widget", 1) }, without_name_match)
      assert.are.equal("widget-pressing", out[1].name)
    end)

    it("falls back to the alphabetically first producer", function()
      local out = find(
        { sig("item", "scrap", 1) },
        { recipe("zzz-recycling", { item("scrap") }), producers[1] }
      )
      assert.are.equal("aaa-byproduct", out[1].name)
    end)
  end)

  it("only considers recipes in the machine's crafting categories", function()
    local recipes = {
      recipe("steel-plate", { item("steel-plate") }, { categories = { "smelting" } }),
      recipe("steel-casting", { item("steel-plate") }, { categories = { "casting" } }),
    }
    local out = find({ sig("item", "steel-plate", 1) }, recipes, { casting = true })
    assert.are.same({
      { type = "recipe", name = "steel-casting", quality = "normal", count = 1 },
    }, out)
  end)

  it("never picks hidden or parameter recipes", function()
    local recipes = {
      recipe("hidden-widget", { item("widget") }, { hidden = true }),
      recipe("parameter-widget", { item("widget") }, { parameter = true }),
      recipe("zz-widget", { item("widget") }),
    }
    local out = find({ sig("item", "widget", 1) }, recipes)
    assert.are.equal("zz-widget", out[1].name)
  end)

  it("drops inputs with no qualifying producer", function()
    local out = find(
      { sig("item", "raw-fish", 1), sig("item", "iron-gear-wheel", 2) },
      { recipe("iron-gear-wheel", { item("iron-gear-wheel") }) }
    )
    assert.are.same({
      { type = "recipe", name = "iron-gear-wheel", quality = "normal", count = 2 },
    }, out)
  end)

  it("drops non-item/fluid signals and zero counts", function()
    local recipes = { recipe("iron-gear-wheel", { item("iron-gear-wheel") }) }
    local out = find({
      sig("recipe", "iron-gear-wheel", 1),
      sig("virtual", "signal-A", 1),
      sig("item", "iron-gear-wheel", 0),
    }, recipes)
    assert.are.same({}, out)
  end)

  it("distinguishes an item and a fluid with the same name", function()
    local recipes = {
      recipe("barrelling", { item("water") }),
      recipe("water", { fluid("water") }),
    }
    local out = find({ sig("fluid", "water", 1) }, recipes)
    assert.are.equal("water", out[1].name)
  end)

  it("inherits the input signal's quality", function()
    local out = find(
      { sig("item", "iron-gear-wheel", 3, "legendary") },
      { recipe("iron-gear-wheel", { item("iron-gear-wheel") }) }
    )
    assert.are.same({
      { type = "recipe", name = "iron-gear-wheel", quality = "legendary", count = 3 },
    }, out)
  end)

  it("sums inputs resolving to the same recipe at the same quality", function()
    local oil = recipe("advanced-oil-processing", { fluid("heavy-oil"), fluid("light-oil") })
    local out = find(
      { sig("fluid", "heavy-oil", 10), sig("fluid", "light-oil", 5) },
      { oil }
    )
    assert.are.same({
      { type = "recipe", name = "advanced-oil-processing", quality = "normal", count = 15 },
    }, out)
  end)

  it("sorts the output by recipe name then quality", function()
    local recipes = {
      recipe("copper-cable", { item("copper-cable") }),
      recipe("iron-gear-wheel", { item("iron-gear-wheel") }),
    }
    local out = find({
      sig("item", "iron-gear-wheel", 1),
      sig("item", "copper-cable", 1, "rare"),
      sig("item", "copper-cable", 1),
    }, recipes)
    local keys = {}
    for i, signal in ipairs(out) do
      keys[i] = signal.name .. "/" .. signal.quality
    end
    assert.are.same({
      "copper-cable/normal",
      "copper-cable/rare",
      "iron-gear-wheel/normal",
    }, keys)
  end)

  it("returns an empty output for an empty input", function()
    assert.are.same({}, find({}, {}))
  end)

  describe("Filters", function()
    local RESEARCHED_ONLY = { researched_only = true, no_fluid_inputs = false }
    local NO_FLUID = { researched_only = false, no_fluid_inputs = true }

    it("researched-only excludes unresearched recipes", function()
      local recipes = { recipe("widget", { item("widget") }) }
      local out = find({ sig("item", "widget", 1) }, recipes, nil, RESEARCHED_ONLY, {})
      assert.are.same({}, out)
      out = find({ sig("item", "widget", 1) }, recipes, nil, RESEARCHED_ONLY, { widget = true })
      assert.are.equal("widget", out[1].name)
    end)

    it("no-fluid-inputs excludes recipes with fluid ingredients", function()
      local recipes = {
        recipe("widget", { item("widget") }, { has_fluid_ingredient = true }),
      }
      local out = find({ sig("item", "widget", 1) }, recipes, nil, NO_FLUID)
      assert.are.same({}, out)
    end)

    it("filters apply before the tie-break: a filtered-out name match falls through", function()
      local recipes = {
        recipe("widget", { item("widget") }),
        recipe("widget-pressing", { item("widget") }, { main_product = item("widget") }),
      }
      local out = find(
        { sig("item", "widget", 1) },
        recipes,
        nil,
        RESEARCHED_ONLY,
        { ["widget-pressing"] = true }
      )
      assert.are.equal("widget-pressing", out[1].name)
    end)

    it("filters combine", function()
      local recipes = {
        recipe("a-widget", { item("widget") }, { has_fluid_ingredient = true }),
        recipe("b-widget", { item("widget") }),
        recipe("c-widget", { item("widget") }),
      }
      local out = find(
        { sig("item", "widget", 1) },
        recipes,
        nil,
        { researched_only = true, no_fluid_inputs = true },
        { ["a-widget"] = true, ["c-widget"] = true }
      )
      assert.are.equal("c-widget", out[1].name)
    end)
  end)
end)
