local memory_cell = require("domain.memory_cell")

local function sig(type, name, count, quality)
  return { type = type, name = name, quality = quality or "normal", count = count }
end

local W = { type = "virtual", name = "signal-W" }

describe("domain.memory_cell.condition_holds", function()
  it("never holds without a first signal", function()
    assert.is_false(memory_cell.condition_holds({ sig("virtual", "signal-W", 1) }, nil))
    assert.is_false(memory_cell.condition_holds({ sig("virtual", "signal-W", 1) },
      { comparator = ">", constant = 0 }))
  end)

  it("treats absent signals as 0", function()
    assert.is_true(memory_cell.condition_holds({},
      { first = W, comparator = "=", constant = 0 }))
    assert.is_false(memory_cell.condition_holds({},
      { first = W, comparator = ">", constant = 0 }))
  end)

  it("compares against a second signal when present, else the constant", function()
    local frame = { sig("virtual", "signal-W", 3), sig("item", "iron-plate", 5) }
    assert.is_true(memory_cell.condition_holds(frame,
      { first = W, comparator = "<", second = { type = "item", name = "iron-plate" } }))
    -- A second signal beats the constant: 3 > 5 is false even though 3 > 0.
    assert.is_false(memory_cell.condition_holds(frame,
      { first = W, comparator = ">", second = { type = "item", name = "iron-plate" }, constant = 0 }))
    assert.is_true(memory_cell.condition_holds(frame,
      { first = W, comparator = ">", constant = 0 }))
  end)

  it("distinguishes qualities of the same signal", function()
    local frame = { sig("item", "iron-plate", 10, "rare") }
    assert.is_false(memory_cell.condition_holds(frame,
      { first = { type = "item", name = "iron-plate" }, comparator = ">", constant = 0 }))
    assert.is_true(memory_cell.condition_holds(frame,
      { first = { type = "item", name = "iron-plate", quality = "rare" }, comparator = ">", constant = 0 }))
  end)

  it("supports every comparator including ASCII aliases", function()
    local frame = { sig("virtual", "signal-W", 5) }
    local cases = {
      { "<", 6, true }, { ">", 4, true }, { "=", 5, true },
      { "≥", 5, true }, { "≤", 5, true }, { "≠", 4, true },
      { ">=", 6, false }, { "<=", 4, false }, { "!=", 5, false },
    }
    for _, case in ipairs(cases) do
      assert.are.equal(case[3], memory_cell.condition_holds(frame,
        { first = W, comparator = case[1], constant = case[2] }),
        case[1] .. " " .. case[2])
    end
  end)
end)

describe("domain.memory_cell.step", function()
  local TRUE_CONDITION = { first = W, comparator = ">", constant = 0 }
  local stored = { sig("item", "copper-plate", 7) }

  it("replaces the Stored Frame with the entire input while the condition holds", function()
    local frame = { sig("virtual", "signal-W", 1), sig("item", "iron-plate", 42) }
    assert.are.equal(frame, memory_cell.step(stored, frame, TRUE_CONDITION))
  end)

  it("keeps the Stored Frame while the condition is false", function()
    local frame = { sig("virtual", "signal-W", 0), sig("item", "iron-plate", 42) }
    assert.are.equal(stored, memory_cell.step(stored, frame, TRUE_CONDITION))
    assert.are.equal(stored, memory_cell.step(stored, {}, TRUE_CONDITION))
  end)

  it("clears the cell when the condition holds on an empty input", function()
    local clear_on_empty = { first = W, comparator = "=", constant = 0 }
    local result = memory_cell.step(stored, {}, clear_on_empty)
    assert.are.same({}, result)
  end)

  it("evaluates the condition against the same frame that gets stored", function()
    -- W=1 rides in with the data; the whole frame including W is stored.
    local frame = { sig("virtual", "signal-W", 1), sig("item", "iron-plate", 3) }
    local result = memory_cell.step({}, frame, TRUE_CONDITION)
    assert.are.equal(frame, result)
    assert.are.equal(2, #result)
  end)
end)
