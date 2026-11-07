-- scripts/planner.lua
-- Pure maths: how many machines does a product rate need?
-- It never touches the game (no `game`, no `prototypes`), so it can be tested
-- outside Factorio. The caller passes in plain tables with the numbers.

local planner = {}

-- Decimal numbers like 3.2 cannot be stored exactly, so 18.75 / 18.749999999999996
-- can come out as 1.0000000000000002 and round up to a whole extra machine.
-- Subtracting a tiny amount before rounding up avoids that.
local EPSILON = 1e-9

-- An inserter drops items on the FAR lane of a belt (the right-hand lane when the
-- belt points straight at it), so the output inserters of a machine fill only one
-- lane of a plain output belt. The layout winds the belt when a machine has
-- exactly this many output inserters, so that each fills a different lane (see
-- layout.lua); the product then travels on both lanes.
local WINDING_OUTPUT_INSERTERS = 2

-- Add up how many of `item_name` one craft of the recipe makes.
---@param recipe bpgen.Recipe
---@param item_name string
---@return number
local function amount_made(recipe, item_name)
  ---@type number
  local total = 0
  for _, product in ipairs(recipe.products) do
    if product.name == item_name then
      total = total + product.amount
    end
  end
  return total
end

-- How many items ONE LANE of a belt carries per minute, from the belt's speed
-- (the `belt_speed` of the belt entity prototype). The prototype docs define the
-- speed as tiles travelled per tick relative to a full belt, and a full lane holds
-- 4 items per tile, so a lane moves belt_speed * 4 items/tick * 60 ticks/second.
-- (The standard belt's speed, 0.03125, gives 7.5 items/s, which is 450 per minute.)
local ITEMS_PER_LANE_PER_TILE = 4
local TICKS_PER_SECOND = 60
local SECONDS_PER_MINUTE = 60

---@param belt_speed number  the belt entity prototype's `belt_speed`
---@return number
function planner.lane_items_per_minute(belt_speed)
  return belt_speed * ITEMS_PER_LANE_PER_TILE * TICKS_PER_SECOND * SECONDS_PER_MINUTE
end

-- How many items ONE INSERTER moves per minute, from its rotation speed (the
-- inserter prototype's `get_inserter_rotation_speed()`, in turns per tick). One
-- swing, which is one full turn there and back, moves one item, so an inserter
-- makes rotation_speed * 60 ticks * 60 seconds swings a minute. (The basic
-- inserter's 0.014 gives 50.4, which matches its known 0.83 swings a second.)
-- Ignores stack size bonuses, so a researched bonus only adds spare capacity, and
-- ignores the slowdown of picking items off a moving belt.
---@param rotation_speed number
---@return number
function planner.inserter_items_per_minute(rotation_speed)
  return rotation_speed * TICKS_PER_SECOND * SECONDS_PER_MINUTE
end

-- Whether this planner can handle the recipe: it must make the product (and
-- only the product, or the machine's output would clog with the rest), and take
-- time to craft.
---@param recipe bpgen.Recipe
---@param product_name string
---@return boolean
local function is_supported(recipe, product_name)
  return amount_made(recipe, product_name) > 0 and #recipe.products == 1 and recipe.energy > 0
end

-- The two lanes of the input belt, one item on each, or nil when the items do not
-- fit. The items are the ingredients plus the fuel, if the machine burns one:
--   one item (an ingredient, no fuel)   it fills both lanes
--   two items (ingredient and fuel, or two ingredients)   one lane each
---@param ingredients bpgen.RecipeItem[]
---@param fuel string|nil
---@return string[]|nil lanes  the item on the first lane, then on the second
local function assign_lanes(ingredients, fuel)
  local items = {}
  for _, ingredient in ipairs(ingredients) do
    items[#items + 1] = ingredient.name
  end
  if fuel then
    items[#items + 1] = fuel
  end
  if #ingredients == 0 or #items > 2 then
    return nil
  end
  return {items[1], items[2] or items[1]}
end

-- How many of the two input lanes carry this item.
---@param lanes string[]
---@param item_name string
---@return integer
local function lanes_carrying(lanes, item_name)
  local count = 0
  for _, lane_item in ipairs(lanes) do
    if lane_item == item_name then
      count = count + 1
    end
  end
  return count
end

-- How many items a minute these inputs add up to.
---@param inputs bpgen.PlanInput[]
---@return number
local function total_per_minute(inputs)
  ---@type number
  local total = 0
  for _, input in ipairs(inputs) do
    total = total + input.per_minute
  end
  return total
end

-- How much of its full speed a machine can use on one side: 1 unless the flow
-- of that side (items a minute) is more than its inserters can move.
---@param flow number
---@param most_movable number
---@return number
local function side_fraction(flow, most_movable)
  if flow <= most_movable then
    return 1
  end
  return most_movable / flow
end

-- How much of its full speed a machine can use: what the side that its
-- inserters hold back the most allows.
---@param input_flow number
---@param output_flow number
---@param inserters bpgen.InserterLimits|nil
---@return number
local function usable_fraction(input_flow, output_flow, inserters)
  if not inserters then
    return 1
  end
  return math.min(
    side_fraction(input_flow, inserters.max_input * inserters.items_per_minute),
    side_fraction(output_flow, inserters.max_output * inserters.items_per_minute))
end

-- How many inserters one side of a machine needs to carry `items_per_machine` a
-- minute. Without an inserter limit one is enough.
---@param items_per_machine number
---@param inserters bpgen.InserterLimits|nil
---@return integer
local function inserters_needed(items_per_machine, inserters)
  if not inserters then
    return 1
  end
  return math.max(1, math.ceil(items_per_machine / inserters.items_per_minute - EPSILON))
end

---@class bpgen.MachineRates  what ONE machine does each minute, once its inserters are counted
---@field output number  items of the product it makes
---@field inputs bpgen.PlanInput[]  what it eats, per ingredient, in the recipe's order
---@field input_inserters integer  on its input side
---@field output_inserters integer  on its output side

-- What ONE machine does each minute. When the inserters cannot keep up with it at
-- full speed, it simply waits for items, so every number shrinks by the same
-- fraction, and the inserters are counted for what it really moves.
---@param request bpgen.StageRequest
---@return bpgen.MachineRates
local function rates_per_machine(request)
  local recipe = request.recipe
  local crafts_per_minute = 60 * request.machine_speed / recipe.energy
  local output = crafts_per_minute * amount_made(recipe, request.product)
  local inputs = {}
  for _, ingredient in ipairs(recipe.ingredients) do
    inputs[#inputs + 1] = {name = ingredient.name, per_minute = crafts_per_minute * ingredient.amount}
  end
  local fraction = usable_fraction(total_per_minute(inputs), output, request.inserters)
  for _, input in ipairs(inputs) do
    input.per_minute = input.per_minute * fraction
  end
  output = output * fraction
  return {
    output = output,
    inputs = inputs,
    input_inserters = inserters_needed(total_per_minute(inputs), request.inserters),
    output_inserters = inserters_needed(output, request.inserters),
  }
end

-- How many whole machines it takes to do `machines_worth` of work: a fraction of a
-- machine still needs a whole one, and a stage always has at least one.
---@param machines_worth number
---@return integer
local function whole_machines(machines_worth)
  return math.max(1, math.ceil(machines_worth - EPSILON))
end

---@param rate_per_minute number
---@param output_per_machine number
---@return integer
local function machines_needed(rate_per_minute, output_per_machine)
  return whole_machines(rate_per_minute / output_per_machine)
end

-- How many machines' worth of product the output belt can take. With one output
-- inserter per machine the product is on one lane, which carries all of it. With
-- two, the winding belt (only the last stage's output belt winds) gives each
-- inserter a lane, but the first inserter takes all it can, so a lane can get
-- everything one inserter moves from every machine. (That is also why the two
-- lanes together never overfill: no machine makes more than two inserters move.)
-- An output belt that does not wind carries everything on its one lane, whatever
-- the inserters.
---@param stage bpgen.StageContext
---@return number
local function output_machines_worth(stage)
  local lane_flow_per_machine = stage.per_machine.output
  if stage.winds and stage.per_machine.output_inserters == WINDING_OUTPUT_INSERTERS and stage.request.inserters then
    lane_flow_per_machine = stage.request.inserters.items_per_minute
  end
  return stage.lane_items_per_minute / lane_flow_per_machine
end

-- How many machines' worth of work the belts of one column can carry before a lane
-- is full: the output belt, and the lanes that carry each ingredient (two lanes for
-- an ingredient that has the belt to itself). It is not a whole number: the belts
-- set the limit, so a column whose belts carry 4.5 machines' worth gets 5 machines,
-- and the last works at half speed.
---@param stage bpgen.StageContext
---@return number
local function machines_per_belt(stage)
  local most = output_machines_worth(stage)
  for _, input in ipairs(stage.per_machine.inputs) do
    local lanes = lanes_carrying(stage.lanes, input.name)
    most = math.min(most, lanes * stage.lane_items_per_minute / input.per_minute)
  end
  return most
end

-- What all the machines eat together, in the recipe's order.
---@param inputs_per_machine bpgen.PlanInput[]
---@param machines number
---@return bpgen.PlanInput[]
local function total_inputs(inputs_per_machine, machines)
  local totals = {}
  for _, input in ipairs(inputs_per_machine) do
    totals[#totals + 1] = {name = input.name, per_minute = machines * input.per_minute}
  end
  return totals
end

---@class bpgen.StageContext  what the planner works out about one stage before it is asked for a rate
---@field request bpgen.StageRequest
---@field previous? bpgen.StageContext  the stage whose product feeds this one; nil for the first stage
---@field lane_items_per_minute number
---@field lanes string[]  the item on each lane of the belt that feeds the stage
---@field winds boolean  whether this stage's output belt may wind (only the last stage's can)
---@field per_machine bpgen.MachineRates
---@field eats_per_minute number  what one machine eats, all ingredients together (a later stage eats only the product of the stage before)
---@field machines_worth number  how many machines' worth of work the belts of a column carry before a lane is full (not a whole number)

-- The items on the lanes of the belt that feeds a stage, or nil when they do not
-- fit. The first stage takes raw items, which share the two lanes (see
-- `assign_lanes`). Every later stage takes the product of the stage before it, and
-- nothing else (nothing could put a second item or a fuel on that belt), on the
-- one lane that product travels on.
---@param stage bpgen.StageRequest
---@param previous bpgen.StageContext|nil  the stage before it, nil for the first stage
---@return string[]|nil lanes
local function stage_lanes(stage, previous)
  if not previous then
    return assign_lanes(stage.recipe.ingredients, stage.fuel)
  end
  local ingredients = stage.recipe.ingredients
  if #ingredients ~= 1 or ingredients[1].name ~= previous.request.product or stage.fuel then
    return nil
  end
  return {ingredients[1].name}
end

-- Everything the planner works out about one stage before it is asked for a rate,
-- or nil when the stage does not fit (see `stage_lanes`, `is_supported`). Only the
-- last stage of the request may wind its output belt.
---@param request bpgen.ChainRequest
---@param stage bpgen.StageRequest  one of the request's stages
---@param previous bpgen.StageContext|nil  the stage before it, nil for the first stage
---@return bpgen.StageContext|nil
local function stage_context(request, stage, previous)
  local lanes = stage_lanes(stage, previous)
  if not lanes or not is_supported(stage.recipe, stage.product) then
    return nil
  end
  local per_machine = rates_per_machine(stage)
  ---@type bpgen.StageContext
  local context = {
    request = stage,
    previous = previous,
    lane_items_per_minute = request.lane_items_per_minute,
    lanes = lanes,
    winds = stage == request.stages[#request.stages],
    per_machine = per_machine,
    eats_per_minute = total_per_minute(per_machine.inputs),
    machines_worth = 0,
  }
  context.machines_worth = machines_per_belt(context)
  return context
end

-- The last stage of the request, which links back through `previous` to all the
-- others, or nil when some stage does not fit (or the request has no stages).
---@param request bpgen.ChainRequest
---@return bpgen.StageContext|nil
local function last_stage_of(request)
  local last
  for _, stage in ipairs(request.stages) do
    last = stage_context(request, stage, last)
    if not last then
      return nil
    end
  end
  return last
end

-- Goes through the stages from `last` back to the first, like `ipairs` in reverse.
---@param last bpgen.StageContext
---@return fun(): bpgen.StageContext|nil
local function stages_backwards(last)
  ---@type bpgen.StageContext|nil
  local next_stage = last
  return function()
    local stage = next_stage
    next_stage = stage and stage.previous
    return stage
  end
end

-- How many machines each stage gets for `rate_per_minute` of the last stage's
-- product. The last stage gets as many as the rate needs. Each earlier stage gets
-- as many as make what the machines of the stage after it eat, but a machine the
-- belts cannot feed only waits, so the stage after it counts for no more than its
-- belts carry, and no stage gets more machines than its own belts carry.
---@param last bpgen.StageContext
---@param rate_per_minute number
---@return table<bpgen.StageContext, integer>
local function machines_for(last, rate_per_minute)
  local machines = {[last] = machines_needed(rate_per_minute, last.per_machine.output)}
  for stage in stages_backwards(last) do
    local previous = stage.previous
    if previous then
      local working = math.min(machines[stage], stage.machines_worth)
      local eaten = working * stage.eats_per_minute
      machines[previous] = math.min(
        machines_needed(eaten, previous.per_machine.output),
        whole_machines(previous.machines_worth))
    end
  end
  return machines
end

-- The most of the last stage's product that the stages make together, in items a
-- minute. A stage makes what its machines make (`machines` says how many it has; nil
-- for as many as its belts carry), but no more than its belts carry, and the last
-- stage can only make as much as the product of every earlier stage allows.
---@param last bpgen.StageContext
---@param machines? table<bpgen.StageContext, integer>
---@return number
local function final_output(last, machines)
  ---@type number
  local most = math.huge
  local needed = 1 -- items of the stage's product made for each item of the last stage's
  ---@type bpgen.StageContext|nil
  local stage_after
  for stage in stages_backwards(last) do
    if stage_after then
      needed = needed * stage_after.eats_per_minute / stage_after.per_machine.output
    end
    local working = math.min(machines and machines[stage] or math.huge, stage.machines_worth)
    most = math.min(most, working * stage.per_machine.output / needed)
    stage_after = stage
  end
  return most
end

-- `machines` machines are built, but those past what the belts carry only wait, so
-- the stage makes and eats what its belts carry.
---@param stage bpgen.StageContext
---@param machines integer
---@return bpgen.Plan
local function stage_plan(stage, machines)
  local working = math.min(machines, stage.machines_worth)
  return {
    machines = machines,
    output_per_minute = working * stage.per_machine.output,
    inputs = total_inputs(stage.per_machine.inputs, working),
    lanes = stage.lanes,
    input_inserters = stage.per_machine.input_inserters,
    output_inserters = stage.per_machine.output_inserters,
  }
end

-- One plan per stage, first stage first. What the last stage makes is what all the
-- stages make together.
---@param last bpgen.StageContext
---@param machines table<bpgen.StageContext, integer>
---@return bpgen.Plan[]
local function plans_of(last, machines)
  local plans = {}
  for stage in stages_backwards(last) do
    local plan = stage_plan(stage, machines[stage])
    if stage == last then
      plan.output_per_minute = final_output(last, machines)
    end
    table.insert(plans, 1, plan)
  end
  return plans
end

-- request.rate_per_minute         how many of the last stage's product per minute
-- request.lane_items_per_minute   how many items one belt lane can carry per minute
-- request.stages                  the stages in order, from the one fed raw items to
--                                 the one that makes what the player wants; each
--                                 stage is
--   {product = item name, recipe = {energy = seconds,
--                                   ingredients = {{name = ..., amount = ...}},
--                                   products = {{name = ..., amount = ...}}},
--    machine_speed = the machine's crafting speed,
--    fuel = optional item the machine burns (first stage only; it takes one lane
--           of the input belt),
--    inserters = optional {items_per_minute, max_input, max_output}: how much one
--           inserter moves, and how many inserters the input side and the output
--           side of a machine get. A machine that would need more runs slower, at
--           what they can move. Two output inserters put the product on both lanes
--           of the output belt, but only for the last stage}
--
-- The first stage's ingredients and its fuel share the two lanes of the input belt:
-- one item fills both lanes, two items get a lane each, and more are refused. A later
-- stage's belt is the belt before it, so it must eat only the product of the stage
-- before, which travels on one lane.
--
-- On success returns one plan table per stage, in the same order:
--   {machines, output_per_minute, inputs, lanes, input_inserters, output_inserters}
--   inputs   {{name, per_minute}, ...} what the machines eat in total, per ingredient
--   lanes    the item on each lane of the input belt (two entries for the first
--            stage, one for a later stage)
--   *_inserters  inserters per machine, on each side
-- Each stage makes what the stage after it eats, and the last makes at least the
-- rate asked.
-- On failure returns nil, a reason string, and sometimes an extra value:
--   "unsupported-recipe"        a stage does not fit the belts, makes more than one
--                               product, or is not made by its product
--   "rate-too-high", max_rate   a belt lane cannot carry that rate, in some stage;
--                               max_rate is the most the last stage can make per
--                               minute in a single column
--
-- Belt limits are counted in fractions of a machine (`machines_worth`): a lane that
-- carries 4.5 machines' worth feeds 5 machines, and the rate is limited by the lane.
---@param request bpgen.ChainRequest
---@return bpgen.Plan[]|nil plans
---@return bpgen.PlanReason|nil reason
---@return number|nil max_rate  only with "rate-too-high"
function planner.plan_chain(request)
  local last = last_stage_of(request)
  if not last then
    return nil, "unsupported-recipe"
  end

  local most = final_output(last)
  if request.rate_per_minute > most + EPSILON then
    return nil, "rate-too-high", most
  end
  return plans_of(last, machines_for(last, request.rate_per_minute))
end

-- One stage on its own: `plan_chain` with a single stage. The request has the
-- fields of a chain request's one stage, plus `rate_per_minute` and
-- `lane_items_per_minute`, and the answer is that stage's plan.
---@param request bpgen.PlanRequest
---@return bpgen.Plan|nil plan
---@return bpgen.PlanReason|nil reason
---@return number|nil max_rate  only with "rate-too-high"
function planner.plan(request)
  local plans, reason, max_rate = planner.plan_chain{
    rate_per_minute = request.rate_per_minute,
    lane_items_per_minute = request.lane_items_per_minute,
    stages = {request},
  }
  if not plans then
    return nil, reason, max_rate
  end
  return plans[1]
end

return planner
