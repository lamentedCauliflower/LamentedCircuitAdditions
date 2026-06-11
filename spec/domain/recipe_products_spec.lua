local recipe_products = require("domain.recipe_products")

local function sig(type, name, count, quality)
  return { type = type, name = name, quality = quality or "normal", count = count }
end

local PRODUCTS = {
  ["iron-gear-wheel"] = { { type = "item", name = "iron-gear-wheel", amount = 1 } },
  ["copper-cable"] = { { type = "item", name = "copper-cable", amount = 2 } },
  ["advanced-oil-processing"] = {
    { type = "fluid", name = "heavy-oil", amount = 25 },
    { type = "fluid", name = "light-oil", amount = 45 },
    { type = "fluid", name = "petroleum-gas", amount = 55 },
  },
  ["uranium-processing"] = {
    { type = "item", name = "uranium-235", amount = 1 },
    { type = "item", name = "uranium-238", amount = 1 },
  },
  ["variable-yield"] = { { type = "item", name = "scrap", amount_min = 2, amount_max = 5 } },
}

describe("domain.recipe_products.map", function()
  it("maps each recipe signal to its products at nominal per-craft amounts", function()
    local out = recipe_products.map({ sig("recipe", "copper-cable", 1) }, PRODUCTS)
    assert.are.same({
      { type = "item", name = "copper-cable", quality = "normal", count = 2 },
    }, out)
  end)

  it("emits every product of a multi-product recipe, sorted by type then name", function()
    local out = recipe_products.map({ sig("recipe", "advanced-oil-processing", 1) }, PRODUCTS)
    assert.are.same({
      { type = "fluid", name = "heavy-oil", quality = "normal", count = 25 },
      { type = "fluid", name = "light-oil", quality = "normal", count = 45 },
      { type = "fluid", name = "petroleum-gas", quality = "normal", count = 55 },
    }, out)
  end)

  it("ignores probability: probabilistic products keep their nominal amount", function()
    -- uranium-processing's U-235 is probability 0.007 in the prototype data;
    -- the products table carries only the nominal amount, which survives.
    local out = recipe_products.map({ sig("recipe", "uranium-processing", 1) }, PRODUCTS)
    assert.are.same({
      { type = "item", name = "uranium-235", quality = "normal", count = 1 },
      { type = "item", name = "uranium-238", quality = "normal", count = 1 },
    }, out)
  end)

  it("values amount ranges at the rounded average of min and max", function()
    -- (2 + 5) / 2 = 3.5 -> 4
    local out = recipe_products.map({ sig("recipe", "variable-yield", 1) }, PRODUCTS)
    assert.are.equal(4, out[1].count)
  end)

  it("ignores input values, treating any nonzero count as presence", function()
    local one = recipe_products.map({ sig("recipe", "copper-cable", 1) }, PRODUCTS)
    local big = recipe_products.map({ sig("recipe", "copper-cable", 123456) }, PRODUCTS)
    local negative = recipe_products.map({ sig("recipe", "copper-cable", -5) }, PRODUCTS)
    assert.are.same(one, big)
    assert.are.same(one, negative)
  end)

  it("drops zero-count recipe signals", function()
    local out = recipe_products.map({ sig("recipe", "copper-cable", 0) }, PRODUCTS)
    assert.are.same({}, out)
  end)

  it("drops non-recipe signals and unknown recipes", function()
    local out = recipe_products.map({
      sig("item", "iron-plate", 10),
      sig("fluid", "water", 3),
      sig("virtual", "signal-A", 1),
      sig("recipe", "not-a-recipe", 1),
    }, PRODUCTS)
    assert.are.same({}, out)
  end)

  it("sums the nominal amounts of a product shared by several input recipes", function()
    local shared = {
      ["a"] = { { type = "item", name = "iron-plate", amount = 2 } },
      ["b"] = { { type = "item", name = "iron-plate", amount = 3 } },
    }
    local out = recipe_products.map(
      { sig("recipe", "a", 1), sig("recipe", "b", 1) },
      shared
    )
    assert.are.same({
      { type = "item", name = "iron-plate", quality = "normal", count = 5 },
    }, out)
  end)

  it("sorts the combined output of several recipes", function()
    local out = recipe_products.map(
      { sig("recipe", "advanced-oil-processing", 1), sig("recipe", "iron-gear-wheel", 1) },
      PRODUCTS
    )
    local names = {}
    for i, signal in ipairs(out) do
      names[i] = signal.type .. "/" .. signal.name
    end
    assert.are.same({
      "fluid/heavy-oil",
      "fluid/light-oil",
      "fluid/petroleum-gas",
      "item/iron-gear-wheel",
    }, names)
  end)

  it("returns an empty output for an empty input", function()
    assert.are.same({}, recipe_products.map({}, PRODUCTS))
  end)

  it("item products inherit the input recipe signal's quality", function()
    local out = recipe_products.map({ sig("recipe", "copper-cable", 1, "legendary") }, PRODUCTS)
    assert.are.same({
      { type = "item", name = "copper-cable", quality = "legendary", count = 2 },
    }, out)
  end)

  it("fluid products are always normal, whatever the input quality", function()
    local out = recipe_products.map(
      { sig("recipe", "advanced-oil-processing", 1, "legendary") },
      PRODUCTS
    )
    for _, signal in ipairs(out) do
      assert.are.equal("normal", signal.quality)
    end
  end)

  it("keeps the same item at different qualities as separate signals", function()
    local out = recipe_products.map({
      sig("recipe", "copper-cable", 1, "normal"),
      sig("recipe", "copper-cable", 1, "legendary"),
    }, PRODUCTS)
    assert.are.same({
      { type = "item", name = "copper-cable", quality = "legendary", count = 2 },
      { type = "item", name = "copper-cable", quality = "normal", count = 2 },
    }, out)
  end)

  it("sums shared item products only within the same quality", function()
    local shared = {
      ["a"] = { { type = "item", name = "iron-plate", amount = 2 } },
      ["b"] = { { type = "item", name = "iron-plate", amount = 3 } },
    }
    local out = recipe_products.map({
      sig("recipe", "a", 1, "rare"),
      sig("recipe", "b", 1, "rare"),
      sig("recipe", "b", 1, "normal"),
    }, shared)
    assert.are.same({
      { type = "item", name = "iron-plate", quality = "normal", count = 3 },
      { type = "item", name = "iron-plate", quality = "rare", count = 5 },
    }, out)
  end)

  it("sums shared fluid products across input qualities", function()
    local shared = {
      ["a"] = { { type = "fluid", name = "steam", amount = 10 } },
      ["b"] = { { type = "fluid", name = "steam", amount = 5 } },
    }
    local out = recipe_products.map({
      sig("recipe", "a", 1, "legendary"),
      sig("recipe", "b", 1, "normal"),
    }, shared)
    assert.are.same({
      { type = "fluid", name = "steam", quality = "normal", count = 15 },
    }, out)
  end)
end)
