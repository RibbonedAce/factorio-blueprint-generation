-- scripts/accounting.lua
-- What a blueprint made of the steps of a recipe takes and which machines it has, worked out from the plans of its steps: the raw items, the fuel
-- and the fluids it uses a minute, and the machines of every step for the description. Pure, like scripts/planner.lua.

local planner = require("scripts.planner")

local accounting = {}

-- The steps of a tree, each after the steps that make its ingredients, so that a chain
-- goes from the raw items to the product. Works for steps and for planned steps.
---@param stage {suppliers: table[]}
---@param list table[]
---@return table[]
function accounting.in_order(stage, list)
  for _, supplier in ipairs(stage.suppliers) do
    accounting.in_order(supplier, list)
  end
  list[#list + 1] = stage
  return list
end

---@class bpgen.Demand  how much of one raw item, one fuel or one fluid a step takes a minute
---@field name string
---@field amount number
---@field is_fuel? boolean
---@field is_fluid? boolean  a fluid, which no belt brings in: the pipes do

-- What the steps of a blueprint take in all, by the order each is listed in: the raw items first, then the fuel, then the fluids.
---@class bpgen.DemandTotals
---@field order string[]  the raw items, from the first step
---@field fuel_order string[]
---@field fluid_order string[]
---@field amount table<string, number>

-- Adds the machines of a part made apart to a list of summaries.
---@param summaries bpgen.StageSummary[]
---@param block bpgen.PlannedBlock
local function add_block_summaries(summaries, block)
  for _, summary in ipairs(block.summaries) do
    summaries[#summaries + 1] = summary
  end
end

-- The machines of every step, from the first to the last, for the blueprint's description: those of the part that makes the fluid a step takes come right
-- before the machines of the step.
---@param planned bpgen.PlannedStage
---@return bpgen.StageSummary[]
function accounting.stage_summaries(planned)
  local summaries = {}
  for _, planned_stage in ipairs(accounting.in_order(planned, {})) do
    if planned_stage.block then
      add_block_summaries(summaries, planned_stage.block)
    else
      if planned_stage.fluid_block then
        add_block_summaries(summaries, planned_stage.fluid_block)
      end
      summaries[#summaries + 1] = {machines = planned_stage.plan.machines, machine = planned_stage.stage.machine}
    end
  end
  return summaries
end

-- What one step takes itself a minute when it makes `crafts` crafts a minute: the ingredients
-- no step makes, which are raw, then, in a machine that burns fuel, the fuel the machines burn
-- while crafting, then the fluids the recipe takes.
---@param planned bpgen.PlannedStage
---@param crafts number
---@param made_by table<string, bpgen.PlannedStage>  the steps below it, by the item they make
---@return bpgen.Demand[]
local function own_demand(planned, crafts, made_by)
  local stage, demand = planned.stage, {}
  for _, ingredient in ipairs(stage.recipe.ingredients) do
    if not made_by[ingredient.name] then
      demand[#demand + 1] = {name = ingredient.name, amount = crafts * ingredient.amount}
    end
  end
  if stage.fuel and stage.fuel_use then
    local machines_working = crafts * stage.recipe.energy / (60 * stage.machine_speed)
    demand[#demand + 1] = {name = stage.fuel, amount = machines_working * stage.fuel_use, is_fuel = true}
  end
  for _, fluid in ipairs(stage.recipe.fluids) do
    if not (stage.fluid_supplier and stage.fluid_supplier.fluid == fluid.name) then -- a part of the blueprint makes that one
      demand[#demand + 1] = {name = fluid.name, amount = crafts * fluid.amount, is_fluid = true}
    end
  end
  return demand
end

-- The list of the totals that an entry is noted in.
---@param totals bpgen.DemandTotals
---@param entry bpgen.Demand
---@return string[]
local function order_of(totals, entry)
  if entry.is_fuel then
    return totals.fuel_order
  end
  return entry.is_fluid and totals.fluid_order or totals.order
end

-- Adds what a step takes to the totals, noting an item the first time it is seen.
---@param totals bpgen.DemandTotals
---@param entry bpgen.Demand
local function add_to_totals(totals, entry)
  if not totals.amount[entry.name] then
    totals.amount[entry.name] = 0
    local order = order_of(totals, entry)
    order[#order + 1] = entry.name
  end
  totals.amount[entry.name] = totals.amount[entry.name] + entry.amount
end

-- Adds what a part made apart takes to the totals.
---@param totals bpgen.DemandTotals
---@param block bpgen.PlannedBlock
local function add_block_demand(totals, block)
  for _, raw in ipairs(block.raws) do
    add_to_totals(totals, {name = raw.name, amount = raw.amount, is_fluid = block.fluids[raw.name]})
  end
end

-- The raw items (and the fuel) the blueprint uses, a minute at the rate it really makes: the
-- step is asked to make `makes` items a minute, so it needs so many crafts, so many of each
-- ingredient (the steps that make an ingredient are asked for that much in turn; an
-- ingredient no step makes is raw) and, in a machine that burns fuel, the fuel the machines
-- burn while crafting (see `own_demand`). `totals.order` lists the raw items in the order the
-- steps need them, from the first step; `totals.fuel_order` the fuels, which go after them, and `totals.fluid_order` the fluids.
---@param planned bpgen.PlannedStage  gets its `demand`
---@param makes number  how many of the step's item it is asked for
---@param totals bpgen.DemandTotals
local function add_demand(planned, makes, totals)
  if planned.block then
    add_block_demand(totals, planned.block)
    return
  end
  local crafts = makes / planner.amount_made(planned.stage.recipe, planned.stage.item)
  local made_by = {}
  for _, supplier in ipairs(planned.suppliers) do
    made_by[supplier.stage.item] = supplier
  end
  for _, ingredient in ipairs(planned.stage.recipe.ingredients) do
    if made_by[ingredient.name] then
      add_demand(made_by[ingredient.name], crafts * ingredient.amount, totals)
    end
  end
  planned.demand = own_demand(planned, crafts, made_by)
  for _, entry in ipairs(planned.demand) do
    add_to_totals(totals, entry)
  end
  if planned.fluid_block then
    add_block_demand(totals, planned.fluid_block)
  end
end

-- How much of each raw item, then of each fuel, then of each fluid, the blueprint uses a minute when its
-- machines make what they really make (which can be more than was asked).
---@param planned bpgen.PlannedStage
---@return bpgen.RawAmount[]
function accounting.raw_amounts(planned)
  local totals = {order = {}, fuel_order = {}, fluid_order = {}, amount = {}}
  add_demand(planned, planned.plan.output_per_minute, totals)
  local raws = {}
  for _, names in ipairs({totals.order, totals.fuel_order, totals.fluid_order}) do
    for _, name in ipairs(names) do
      raws[#raws + 1] = {name = name, amount = totals.amount[name]}
    end
  end
  return raws
end

-- What a chain takes in a minute, from the top of the blueprint down: what the steps on belts take (the raw items, then the fuel), the water
-- (of both plants, together, with any other fluid they take that comes in by a pipe) and the crude oil of the machines that make the fluid.
---@param lists bpgen.RawAmount[][]
---@return bpgen.RawAmount[]
function accounting.merged_raws(lists)
  local raws, place = {}, {}
  for _, list in ipairs(lists) do
    for _, raw in ipairs(list) do
      if place[raw.name] then
        raws[place[raw.name]].amount = raws[place[raw.name]].amount + raw.amount
      else
        raws[#raws + 1], place[raw.name] = {name = raw.name, amount = raw.amount}, #raws + 1
      end
    end
  end
  return raws
end

-- The machines of several lists by name, in the order they first come, the sum for a machine that two of them share.
---@param lists bpgen.StageSummary[][]
---@return bpgen.StageSummary[]
function accounting.merged_summaries(lists)
  local order, counts = {}, {}
  for _, list in ipairs(lists) do
    for _, summary in ipairs(list) do
      if not counts[summary.machine] then
        order[#order + 1], counts[summary.machine] = summary.machine, 0
      end
      counts[summary.machine] = counts[summary.machine] + summary.machines
    end
  end
  local merged = {}
  for _, machine in ipairs(order) do
    merged[#merged + 1] = {machines = counts[machine], machine = machine}
  end
  return merged
end

return accounting
