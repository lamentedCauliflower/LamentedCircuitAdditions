-- Pure domain logic: Stack Pack Mode mapping (see CONTEXT.md).
-- Modules under domain/ must not touch the Factorio API so they stay loadable
-- from the busted test suite outside the game.
local stack_pack = {}

-- Signal-identity equality, used to drop the signal chosen as the X source.
local function same_signal(a, b)
  return a ~= nil
    and b ~= nil
    and a.name == b.name
    and (a.type or "item") == (b.type or "item")
    and (a.quality or "normal") == (b.quality or "normal")
end

--- Pack the input item signals into the first `slots` slots and output the
--- amount that fits. Each item (count C, stack size S) lays its slots
--- partial-stack-first ([C mod S, S, S, …], needing ceil(C/S) slots). Items
--- are ordered by count (descending when select_max is not false, else
--- ascending), ties broken by name then quality; their slots are concatenated
--- in that order and the first `slots` kept. Each item outputs the summed
--- amount of its kept slots (boundary item granted k of its ceil(C/S) slots:
--- C - (ceil(C/S) - k)*S). Only items pack; non-item signals, counts <= 0 and
--- the excluded budget signal are dropped. Output preserves the input quality.
--- @param frame table[] combined input signals: { type, name, quality, count }
--- @param stack_sizes table<string, number> item name -> stack size (>= 1)
--- @param slots number slot budget X (floored; <= 0 yields no output)
--- @param select_max boolean order by count descending when not false
--- @param excluded table|nil signal id removed from the pack set
--- @return table[] item signals sorted by name then quality:
---   { type = "item", name, quality, count }
function stack_pack.map(frame, stack_sizes, slots, select_max, excluded)
  slots = math.floor(slots or 0)
  if slots <= 0 then
    return {}
  end
  local items = {}
  for _, signal in ipairs(frame) do
    if
      (signal.type or "item") == "item"
      and signal.count > 0
      and stack_sizes[signal.name]
      and not same_signal(signal, excluded)
    then
      items[#items + 1] = signal
    end
  end
  local descending = select_max ~= false
  table.sort(items, function(a, b)
    if a.count ~= b.count then
      if descending then
        return a.count > b.count
      end
      return a.count < b.count
    end
    if a.name ~= b.name then
      return a.name < b.name
    end
    return (a.quality or "normal") < (b.quality or "normal")
  end)
  local out = {}
  local remaining = slots
  for _, signal in ipairs(items) do
    if remaining <= 0 then
      break
    end
    local stack = stack_sizes[signal.name]
    local count = signal.count
    local needed = math.ceil(count / stack)
    local kept
    if needed <= remaining then
      kept = count
      remaining = remaining - needed
    else
      -- Boundary item: the partial stack fills the first slot, then full
      -- stacks, so only the last (needed - remaining) full stacks fall away.
      kept = count - (needed - remaining) * stack
      remaining = 0
    end
    out[#out + 1] = {
      type = "item",
      name = signal.name,
      quality = signal.quality or "normal",
      count = kept,
    }
  end
  table.sort(out, function(a, b)
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.quality < b.quality
  end)
  return out
end

return stack_pack
