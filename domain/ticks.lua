-- Pure domain logic: crafting-time tick math.
-- Modules under domain/ must not touch the Factorio API so they stay loadable
-- from the busted test suite outside the game.
local ticks = {}

--- Crafting duration in ticks for a recipe on a machine.
--- @param energy number recipe energy (base crafting time in seconds)
--- @param crafting_speed number the machine's crafting speed
--- @return integer
function ticks.crafting_ticks(energy, crafting_speed)
  return math.floor(energy / crafting_speed * 60)
end

return ticks
