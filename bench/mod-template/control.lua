-- Benchmark world builder. bench/bench.py substitutes the __PLACEHOLDERS__
-- and installs this as the temp mod "lca-bench"; on_init runs at --create
-- time, so the world is baked into the save and --benchmark measures pure
-- steady state.
--
-- World: COUNT pairs of [constant-combinator feeder] --red wire--> [DUT
-- selector combinator], on a powered grid. The DUT is a vanilla selector
-- ("select max") or an LCA script Mode, per VARIANT. The "none" variant
-- builds everything except the DUTs, so (variant - none) isolates the
-- per-DUT cost.

local VARIANT = "__VARIANT__"
local COUNT = __COUNT__
local SIGNALS = __SIGNALS__
local DYNAMIC = __DYNAMIC__
local VERIFY = __VERIFY__

local MACHINE = "assembling-machine-2"
local GRID_COLS = 20
local STEP_X, STEP_Y = 8, 4

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

-- Deterministic pool of recipes craftable on MACHINE.
local function machine_recipes()
  local categories = prototypes.entity[MACHINE].crafting_categories
  local out = {}
  for _, name in ipairs(sorted_keys(prototypes.recipe)) do
    local recipe = prototypes.recipe[name]
    if categories[recipe.category] and not recipe.hidden and not recipe.parameter then
      out[#out + 1] = name
    end
  end
  return out
end

-- The feeder's signal list: recipe signals, or item product signals for
-- the Recipe Finder (which maps items back to recipes).
local function feeder_signals()
  local recipes = machine_recipes()
  local out = {}
  if VARIANT == "recipe-finder" then
    local seen = {}
    for _, name in ipairs(recipes) do
      for _, product in ipairs(prototypes.recipe[name].products or {}) do
        if product.type == "item" and not seen[product.name] then
          seen[product.name] = true
          out[#out + 1] = { type = "item", name = product.name }
          if #out == SIGNALS then
            return out
          end
        end
      end
    end
  else
    for i = 1, math.min(SIGNALS, #recipes) do
      out[i] = { type = "recipe", name = recipes[i] }
    end
  end
  return out
end

local function build_power(surface, force, width, height)
  for x = -8, width + 8, 16 do
    for y = -8, height + 8, 16 do
      surface.create_entity{ name = "substation", position = { x, y }, force = force }
    end
  end
  local eei = surface.create_entity{
    name = "electric-energy-interface",
    position = { -6, -6 },
    force = force,
  }
  eei.electric_buffer_size = 1e12
  eei.power_production = 1e9 -- J/tick = 60 GW, plenty for any COUNT
  eei.energy = 1e12
end

local function wire(source, source_connector, dest, dest_connector)
  local a = source.get_wire_connector(source_connector, true)
  local b = dest.get_wire_connector(dest_connector, true)
  b.connect_to(a, false)
end

local function set_feeder_signals(feeder, signals)
  local section = feeder.get_or_create_control_behavior().get_section(1)
  local filters = {}
  for i, signal in ipairs(signals) do
    filters[i] = {
      value = { type = signal.type, name = signal.name, quality = "normal", comparator = "=" },
      min = 1,
    }
  end
  section.filters = filters
end

local function configure_dut(dut, signals)
  if VARIANT == "vanilla" then
    dut.get_or_create_control_behavior().parameters = {
      operation = "select",
      select_max = true,
      index_constant = 0,
    }
  elseif VARIANT == "crafting-time" then
    remote.call("lamented-circuit-additions", "configure_selector", dut, {
      mode = "crafting-time",
      machine = MACHINE,
    })
  elseif VARIANT == "recipe-products" then
    remote.call("lamented-circuit-additions", "configure_selector", dut, {
      mode = "recipe-products",
    })
  elseif VARIANT == "recipe-finder" then
    remote.call("lamented-circuit-additions", "configure_selector", dut, {
      mode = "recipe-finder",
      machine = MACHINE,
      researched_only = true,
      no_fluid = false,
    })
  elseif VARIANT == "memory-cell-hot" or VARIANT == "memory-cell-idle" then
    -- hot: condition holds every tick (worst case, stores each tick);
    -- idle: condition never holds (steady state with a kept Stored Frame).
    local comparator = VARIANT == "memory-cell-hot" and ">" or "<"
    remote.call("lamented-circuit-additions", "configure_selector", dut, {
      mode = "memory-cell",
      condition = {
        first = { type = signals[1].type, name = signals[1].name },
        comparator = comparator,
        constant = 0,
      },
    })
  else
    error("lca-bench: unknown variant " .. VARIANT)
  end
end

script.on_init(function()
  local surface = game.surfaces[1]
  local force = game.forces.player
  force.research_all_technologies()

  local rows = math.ceil(COUNT / GRID_COLS)
  local width, height = GRID_COLS * STEP_X, rows * STEP_Y
  surface.request_to_generate_chunks({ width / 2, height / 2 }, math.ceil(math.max(width, height) / 64) + 2)
  surface.force_generate_chunk_requests()

  build_power(surface, force, width, height)
  local signals = feeder_signals()
  local connector = defines.wire_connector_id

  for i = 0, COUNT - 1 do
    local x = (i % GRID_COLS) * STEP_X
    local y = math.floor(i / GRID_COLS) * STEP_Y

    local feeder = surface.create_entity{
      name = "constant-combinator",
      position = { x, y },
      force = force,
    }
    set_feeder_signals(feeder, signals)

    local input_sources = { { feeder, connector.circuit_red } }
    if DYNAMIC then
      -- A "random signal" selector re-picks one input signal every tick,
      -- so the DUT's input frame changes every tick.
      local randomizer = surface.create_entity{
        name = "selector-combinator",
        position = { x + 4, y },
        force = force,
      }
      randomizer.get_or_create_control_behavior().parameters = {
        operation = "random",
        random_update_interval = 1,
      }
      wire(feeder, connector.circuit_red, randomizer, connector.combinator_input_red)
      input_sources[#input_sources + 1] = { randomizer, connector.combinator_output_red }
    end

    if VARIANT ~= "none" then
      local dut = surface.create_entity{
        name = "selector-combinator",
        position = { x + 2, y },
        force = force,
      }
      for _, source in ipairs(input_sources) do
        wire(source[1], source[2], dut, connector.combinator_input_red)
      end
      if VERIFY and not storage.first_dut then
        -- Probe get_signals merge semantics: the first pair feeds the green
        -- input too, so each signal arrives on both wires.
        wire(feeder, connector.circuit_green, dut, connector.combinator_input_green)
      end
      configure_dut(dut, signals)
      storage.first_dut = storage.first_dut or dut
    end
  end
end)

if VERIFY then
  script.on_event(defines.events.on_tick, function(event)
    if event.tick ~= 5 then
      return
    end
    local connector = defines.wire_connector_id
    local dut = storage.first_dut
    if not (dut and dut.valid) then
      log("LCA-BENCH verify: no DUT (variant=" .. VARIANT .. ")")
      return
    end
    log("LCA-BENCH verify: variant=" .. VARIANT .. " status=" .. tostring(dut.status))
    local input = dut.get_signals(connector.combinator_input_red, connector.combinator_input_green)
    log("LCA-BENCH verify: input signal count=" .. tostring(input and #input or 0))
    if input and input[1] then
      log("LCA-BENCH verify: in[1]= "
        .. (input[1].signal.type or "item") .. "/" .. input[1].signal.name .. "=" .. input[1].count)
    end
    local out = dut.get_signals(connector.combinator_output_red, connector.combinator_output_green)
    log("LCA-BENCH verify: output signal count=" .. tostring(out and #out or 0))
    for i = 1, math.min(3, out and #out or 0) do
      local signal = out[i]
      log("LCA-BENCH verify: out[" .. i .. "]= "
        .. (signal.signal.type or "item") .. "/" .. signal.signal.name .. "=" .. signal.count)
    end
  end)
end
