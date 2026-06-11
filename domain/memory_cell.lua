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

local WILDCARDS = {
  ["signal-everything"] = "everything",
  ["signal-anything"] = "anything",
  ["signal-each"] = "each",
}

local function wildcard_of(signal)
  if signal and (signal.type or "item") == "virtual" then
    return WILDCARDS[signal.name]
  end
  return nil
end

--- Evaluate the Update Condition against a combined input frame and
--- decide what to store. Signals absent from the frame count as 0;
--- without a first signal the condition never holds.
--- Wildcard first signals follow decider semantics: Everything holds
--- when every input signal passes (vacuously true on an empty input),
--- Anything when at least one does. Each stores only the passing subset
--- of the input rather than the whole frame.
--- @param frame table[] combined input signals: { type, name, quality, count }
--- @param condition table { first = signal?, comparator = string,
---   second = signal?, constant = number? } (second beats constant)
--- @return table[]? the frame to store, or nil when the condition holds nothing
function memory_cell.evaluate(frame, condition)
  if not (condition and condition.first) then
    return nil
  end
  local compare = COMPARE[condition.comparator or "<"]
  if not compare then
    return nil
  end
  local lookup = {}
  for _, signal in ipairs(frame) do
    lookup[key(signal)] = signal.count
  end
  local right
  if condition.second then
    right = lookup[key(condition.second)] or 0
  else
    right = condition.constant or 0
  end
  local wildcard = wildcard_of(condition.first)
  if wildcard == "everything" then
    for _, signal in ipairs(frame) do
      if not compare(signal.count, right) then
        return nil
      end
    end
    return frame
  elseif wildcard == "anything" then
    for _, signal in ipairs(frame) do
      if compare(signal.count, right) then
        return frame
      end
    end
    return nil
  elseif wildcard == "each" then
    local passing = {}
    for _, signal in ipairs(frame) do
      if compare(signal.count, right) then
        passing[#passing + 1] = signal
      end
    end
    if #passing > 0 then
      return passing
    end
    return nil
  end
  local left = lookup[key(condition.first)] or 0
  if compare(left, right) then
    return frame
  end
  return nil
end

--- Whether the Update Condition holds (would store something).
function memory_cell.condition_holds(frame, condition)
  return memory_cell.evaluate(frame, condition) ~= nil
end

--- One tick of the Memory Cell. Level-triggered: while the condition
--- holds, the Stored Frame is replaced by what evaluate() yields (the
--- entire input, or the passing subset under Each; an empty input under
--- Everything clears the cell); otherwise the Stored Frame is kept.
--- @param stored table[] the current Stored Frame
--- @param frame table[] combined input signals
--- @param condition table the Update Condition
--- @return table[] the new Stored Frame
function memory_cell.step(stored, frame, condition)
  return memory_cell.evaluate(frame, condition) or stored
end

return memory_cell
