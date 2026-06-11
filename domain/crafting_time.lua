-- Pure domain logic: Crafting-Time Mode mapping (see CONTEXT.md).
-- Modules under domain/ must not touch the Factorio API so they stay loadable
-- from the busted test suite outside the game.
local ticks = require("domain.ticks")

local crafting_time = {}

--- Map a combined input frame to crafting-time recipe signals.
--- Input values are ignored (any nonzero count is a presence flag);
--- non-recipe signals and unknown recipes are dropped.
--- @param frame table[] combined input signals: { type, name, quality, count }
--- @param energies table<string, number> recipe name -> energy (seconds at speed 1)
--- @param crafting_speed number Target Machine crafting speed, > 0
--- @return table[] recipe signals sorted by name then quality:
---   { type = "recipe", name, quality, count = ticks }
function crafting_time.map(frame, energies, crafting_speed)
  local out = {}
  for _, signal in ipairs(frame) do
    if signal.type == "recipe" and signal.count ~= 0 and energies[signal.name] then
      out[#out + 1] = {
        type = "recipe",
        name = signal.name,
        quality = signal.quality,
        count = ticks.crafting_ticks(energies[signal.name], crafting_speed),
      }
    end
  end
  table.sort(out, function(a, b)
    if a.name ~= b.name then
      return a.name < b.name
    end
    return (a.quality or "") < (b.quality or "")
  end)
  return out
end

return crafting_time
