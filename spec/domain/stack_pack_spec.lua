local stack_pack = require("domain.stack_pack")

local function sig(type, name, count, quality)
  return { type = type, name = name, quality = quality or "normal", count = count }
end

-- Stack sizes for the fixtures.
local STACKS = {
  ["iron-plate"] = 100,
  ["copper-plate"] = 100,
  ["copper-cable"] = 200,
  ["iron-gear-wheel"] = 100,
  ["steel-plate"] = 50,
}

describe("domain.stack_pack.map", function()
  it("passes every item through at full count when the budget is ample", function()
    local out = stack_pack.map(
      { sig("item", "iron-plate", 250), sig("item", "steel-plate", 80) },
      STACKS,
      10,
      true
    )
    assert.are.same({
      { type = "item", name = "iron-plate", quality = "normal", count = 250 },
      { type = "item", name = "steel-plate", quality = "normal", count = 80 },
    }, out)
  end)

  it("packs by count descending and cuts the boundary item partial-stack-first", function()
    -- iron 250 (S100) -> slots [50,100,100] = 3; copper-plate 80 (S100) -> 1
    -- highest first: iron then copper-plate. X = 4 -> iron fully (3), 1 slot
    -- left for copper-plate, which needs 1 -> copper-plate fully too.
    local out = stack_pack.map(
      { sig("item", "copper-plate", 80), sig("item", "iron-plate", 250) },
      STACKS,
      4,
      true
    )
    assert.are.same({
      { type = "item", name = "copper-plate", quality = "normal", count = 80 },
      { type = "item", name = "iron-plate", quality = "normal", count = 250 },
    }, out)
  end)

  it("outputs only the remainder when one slot of an over-budget item fits", function()
    -- iron 250 (S100) needs 3 slots; steel 80 (S50) needs 2. Highest first:
    -- iron(3) then steel; X=4 leaves 1 slot for steel -> 80 - (2-1)*50 = 30.
    local out = stack_pack.map(
      { sig("item", "steel-plate", 80), sig("item", "iron-plate", 250) },
      STACKS,
      4,
      true
    )
    assert.are.same({
      { type = "item", name = "iron-plate", quality = "normal", count = 250 },
      { type = "item", name = "steel-plate", quality = "normal", count = 30 },
    }, out)
  end)

  it("keeps the remainder plus full stacks for a multi-slot boundary item", function()
    -- A=230 (S100) -> slots [30,100,100], needs 3; X=2 -> 230 - (3-2)*100 = 130.
    local out = stack_pack.map({ sig("item", "iron-plate", 230) }, STACKS, 2, true)
    assert.are.same({
      { type = "item", name = "iron-plate", quality = "normal", count = 130 },
    }, out)
  end)

  it("orders smallest first under the lowest toggle", function()
    -- gear 40 (S100) needs 1, iron 250 needs 3. Lowest first: gear then iron.
    -- X=1 -> gear fully, no room for iron.
    local out = stack_pack.map(
      { sig("item", "iron-plate", 250), sig("item", "iron-gear-wheel", 40) },
      STACKS,
      1,
      false
    )
    assert.are.same({
      { type = "item", name = "iron-gear-wheel", quality = "normal", count = 40 },
    }, out)
  end)

  it("breaks count ties by name then quality", function()
    -- All count 50 (S50 steel needs 1, S100 others need 1). X=2 keeps the
    -- first two by name: copper-plate, iron-plate (steel-plate drops).
    local out = stack_pack.map({
      sig("item", "steel-plate", 50),
      sig("item", "iron-plate", 50),
      sig("item", "copper-plate", 50),
    }, STACKS, 2, true)
    assert.are.same({
      { type = "item", name = "copper-plate", quality = "normal", count = 50 },
      { type = "item", name = "iron-plate", quality = "normal", count = 50 },
    }, out)
  end)

  it("drops non-item signals, unknown items and counts <= 0", function()
    local out = stack_pack.map({
      sig("fluid", "water", 500),
      sig("recipe", "iron-gear-wheel", 1),
      sig("virtual", "signal-A", 9),
      sig("item", "not-an-item", 100),
      sig("item", "iron-plate", 0),
      sig("item", "copper-plate", -5),
      sig("item", "steel-plate", 30),
    }, STACKS, 10, true)
    assert.are.same({
      { type = "item", name = "steel-plate", quality = "normal", count = 30 },
    }, out)
  end)

  it("excludes the signal chosen as the budget source from packing", function()
    local out = stack_pack.map(
      { sig("item", "iron-plate", 250), sig("item", "copper-plate", 80) },
      STACKS,
      10,
      true,
      { type = "item", name = "iron-plate", quality = "normal" }
    )
    assert.are.same({
      { type = "item", name = "copper-plate", quality = "normal", count = 80 },
    }, out)
  end)

  it("returns an empty output for a zero or negative budget", function()
    assert.are.same({}, stack_pack.map({ sig("item", "iron-plate", 250) }, STACKS, 0, true))
    assert.are.same({}, stack_pack.map({ sig("item", "iron-plate", 250) }, STACKS, -3, true))
  end)

  it("returns an empty output for an empty input", function()
    assert.are.same({}, stack_pack.map({}, STACKS, 5, true))
  end)

  it("packs each (name, quality) independently and preserves quality", function()
    -- legendary iron 250 (S100) needs 3, normal iron 50 needs 1. Highest
    -- first: legendary(250) then normal(50). X=4 keeps both fully.
    local out = stack_pack.map({
      sig("item", "iron-plate", 50, "normal"),
      sig("item", "iron-plate", 250, "legendary"),
    }, STACKS, 4, true)
    assert.are.same({
      { type = "item", name = "iron-plate", quality = "legendary", count = 250 },
      { type = "item", name = "iron-plate", quality = "normal", count = 50 },
    }, out)
  end)
end)
