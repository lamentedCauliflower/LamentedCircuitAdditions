local crafting_time = require("domain.crafting_time")

local function sig(type, name, count, quality)
  return { type = type, name = name, quality = quality or "normal", count = count }
end

local ENERGIES = {
  ["iron-gear-wheel"] = 0.5,
  ["engine-unit"] = 10,
  ["sulfur"] = 1,
}

describe("domain.crafting_time.map", function()
  it("values each recipe signal at its crafting time in ticks", function()
    local out = crafting_time.map(
      { sig("recipe", "iron-gear-wheel", 1), sig("recipe", "engine-unit", 1) },
      ENERGIES, 0.75
    )
    assert.are.same({
      { type = "recipe", name = "engine-unit", quality = "normal", count = 800 },
      { type = "recipe", name = "iron-gear-wheel", quality = "normal", count = 40 },
    }, out)
  end)

  it("floors sub-tick results", function()
    -- 0.5 / 1.25 * 60 = 24 exactly; 1 / 1.25 * 60 = 48; 0.5 / 7 * 60 = 4.28… -> 4
    local fast = crafting_time.map({ sig("recipe", "iron-gear-wheel", 1) }, ENERGIES, 7)
    assert.are.equal(4, fast[1].count)
    local exact = crafting_time.map({ sig("recipe", "sulfur", 1) }, ENERGIES, 1.25)
    assert.are.equal(48, exact[1].count)
  end)

  it("ignores input values, treating any nonzero count as presence", function()
    local one = crafting_time.map({ sig("recipe", "sulfur", 1) }, ENERGIES, 1)
    local big = crafting_time.map({ sig("recipe", "sulfur", 123456) }, ENERGIES, 1)
    local negative = crafting_time.map({ sig("recipe", "sulfur", -5) }, ENERGIES, 1)
    assert.are.equal(60, one[1].count)
    assert.are.same(one, big)
    assert.are.same(one, negative)
  end)

  it("drops zero-count signals", function()
    local out = crafting_time.map({ sig("recipe", "sulfur", 0) }, ENERGIES, 1)
    assert.are.same({}, out)
  end)

  it("drops non-recipe signals", function()
    local out = crafting_time.map({
      sig("item", "iron-plate", 10),
      sig("fluid", "water", 100),
      sig("virtual", "signal-A", 1),
      sig("recipe", "sulfur", 1),
    }, ENERGIES, 1)
    assert.are.same({
      { type = "recipe", name = "sulfur", quality = "normal", count = 60 },
    }, out)
  end)

  it("drops recipes missing from the energy table", function()
    local out = crafting_time.map({ sig("recipe", "unknown-recipe", 1) }, ENERGIES, 1)
    assert.are.same({}, out)
  end)

  it("sorts by name then quality, preserving the input quality", function()
    local out = crafting_time.map({
      sig("recipe", "sulfur", 1, "rare"),
      sig("recipe", "sulfur", 1, "normal"),
      sig("recipe", "engine-unit", 1, "uncommon"),
    }, ENERGIES, 1)
    assert.are.same({
      { type = "recipe", name = "engine-unit", quality = "uncommon", count = 600 },
      { type = "recipe", name = "sulfur", quality = "normal", count = 60 },
      { type = "recipe", name = "sulfur", quality = "rare", count = 60 },
    }, out)
  end)
end)
