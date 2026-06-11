-- Pure domain logic: Memory Cell step (see CONTEXT.md).
-- Modules under domain/ must not touch the Factorio API so they stay loadable
-- from the busted test suite outside the game.
local memory_cell = {}

local COMPARE = {
  ["<"] = function(a, b) return a < b end,
  [">"] = function(a, b) return a > b end,
  ["="] = function(a, b) return a == b end,
  ["≥"] = function(a, b) return a >= b end,
  ["≤"] = function(a, b) return a <= b end,
  ["≠"] = function(a, b) return a ~= b end,
}
COMPARE[">="] = COMPARE["≥"]
COMPARE["<="] = COMPARE["≤"]
COMPARE["!="] = COMPARE["≠"]

local function key(signal)
  return (signal.type or "item") .. "/" .. signal.name .. "/" .. (signal.quality or "normal")
end

--- Evaluate the Update Condition against a combined input frame.
--- Signals absent from the frame count as 0; without a first signal the
--- condition never holds.
--- @param frame table[] combined input signals: { type, name, quality, count }
--- @param condition table { first = signal?, comparator = string,
---   second = signal?, constant = number? } (second beats constant)
--- @return boolean
function memory_cell.condition_holds(frame, condition)
  if not (condition and condition.first) then
    return false
  end
  local compare = COMPARE[condition.comparator or "<"]
  if not compare then
    return false
  end
  local lookup = {}
  for _, signal in ipairs(frame) do
    lookup[key(signal)] = signal.count
  end
  local left = lookup[key(condition.first)] or 0
  local right
  if condition.second then
    right = lookup[key(condition.second)] or 0
  else
    right = condition.constant or 0
  end
  return compare(left, right)
end

--- One tick of the Memory Cell. Level-triggered: while the condition
--- holds, the Stored Frame is replaced by the entire input frame (an
--- empty input clears the cell); otherwise the Stored Frame is kept.
--- Returns the input frame table itself when storing.
--- @param stored table[] the current Stored Frame
--- @param frame table[] combined input signals
--- @param condition table the Update Condition
--- @return table[] the new Stored Frame
function memory_cell.step(stored, frame, condition)
  if memory_cell.condition_holds(frame, condition) then
    return frame
  end
  return stored
end

return memory_cell
