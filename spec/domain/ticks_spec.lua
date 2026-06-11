local ticks = require("domain.ticks")

describe("domain.ticks.crafting_ticks", function()
  it("converts base crafting time to ticks at speed 1", function()
    assert.are.equal(30, ticks.crafting_ticks(0.5, 1))
  end)

  it("scales by crafting speed", function()
    assert.are.equal(40, ticks.crafting_ticks(0.5, 0.75))
  end)

  it("floors fractional ticks", function()
    assert.are.equal(42, ticks.crafting_ticks(1, 1.4))
  end)
end)
