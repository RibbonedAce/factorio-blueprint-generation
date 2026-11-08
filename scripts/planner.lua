-- scripts/planner.lua
-- Pure maths: how many machines does a product rate need?
-- It never touches the game (no `game`, no `prototypes`), so it can be tested
-- outside Factorio. The caller passes in plain tables with the numbers.

local planner = {}

-- Decimal numbers like 3.2 cannot be stored exactly, so 18.75 / 18.749999999999996
-- can come out as 1.0000000000000002 and round up to a whole extra machine.
-- Subtracting a tiny amount before rounding up avoids that.
local EPSILON = 1e-9

-- An inserter drops items on the FAR lane of a belt that runs across its line (on a
-- curve, the inside lane; on a belt in line with it, the lane on the side to the right of
-- the way it faces), so the output inserters of a machine fill only one
-- lane of a plain output belt. The layout winds the belt when a machine has
-- exactly this many output inserters, so that each fills a different lane (see
-- layout.lua); the product then travels on both lanes.
local WINDING_OUTPUT_INSERTERS = 2

-- The input belt of a stage has two lanes, so a stage takes at most this many items
-- from it: its ingredients and its fuel, or one made ingredient on each lane.
local INPUT_LANES = 2

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
  if #ingredients == 0 or #items > INPUT_LANES then
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

-- What one machine eats of `item` in a minute.
---@param inputs bpgen.PlanInput[]  what one machine eats, per ingredient
---@param item string  one of the ingredients
---@return number
local function eaten_of(inputs, item)
  local eaten = 0
  for _, input in ipairs(inputs) do
    if input.name == item then
      eaten = eaten + input.per_minute
    end
  end
  return eaten
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
---@field suppliers bpgen.StageContext[]  the stages whose products it eats, in the order of the recipe's ingredients
---@field lane_items_per_minute number
---@field lanes string[]  the item on each lane of the belt that feeds the stage
---@field winds boolean  whether this stage's output belt may wind (only the root stage's can)
---@field per_machine bpgen.MachineRates
---@field machines_worth number  how many machines' worth of work the belts of a column carry before a lane is full (not a whole number)

-- The items on the lanes of the belt that feeds a stage, or nil when they do not
-- fit. A stage fed raw items shares the two lanes among them and its fuel (see
-- `assign_lanes`). Every other stage eats the products of the stages that feed it,
-- each on the one lane its product travels on, and at most one more item, a raw one
-- on the other lane (nothing could put a fuel on that belt), so it has at most two
-- ingredients. The stages that feed it make ingredients of its recipe, in any order.
---@param stage bpgen.StageRequest
---@param suppliers bpgen.StageContext[]  the stages that feed it
---@return string[]|nil lanes  the ingredients, in the recipe's order
local function stage_lanes(stage, suppliers)
  if #suppliers == 0 then
    return assign_lanes(stage.recipe.ingredients, stage.fuel)
  end
  local ingredients = stage.recipe.ingredients
  if #ingredients > INPUT_LANES or stage.fuel then
    return nil
  end
  local lanes, unmade = {}, {}
  for index, ingredient in ipairs(ingredients) do
    lanes[index] = ingredient.name
    unmade[ingredient.name] = true
  end
  for _, supplier in ipairs(suppliers) do
    if not unmade[supplier.request.product] then
      return nil
    end
    unmade[supplier.request.product] = nil
  end
  return lanes
end

-- Everything the planner works out about a stage and the stages that feed it before
-- it is asked for a rate, or nil when one of them does not fit (see `stage_lanes`,
-- `is_supported`). Only the root stage may wind its output belt.
---@param tree bpgen.StageTree
---@param request bpgen.TreeRequest
---@param is_root boolean
---@return bpgen.StageContext|nil
local function stage_context(tree, request, is_root)
  local suppliers = {}
  for index, supplier in ipairs(tree.suppliers) do
    suppliers[index] = stage_context(supplier, request, false)
    if not suppliers[index] then
      return nil
    end
  end
  local stage = tree.stage
  local lanes = stage_lanes(stage, suppliers)
  if not lanes or not is_supported(stage.recipe, stage.product) then
    return nil
  end
  ---@type bpgen.StageContext
  local context = {
    request = stage, suppliers = suppliers, lane_items_per_minute = request.lane_items_per_minute,
    lanes = lanes, winds = is_root, per_machine = rates_per_machine(stage), machines_worth = 0,
  }
  context.machines_worth = machines_per_belt(context)
  return context
end

-- What the rate asks of every stage of a tree.
---@class bpgen.Sizes
---@field machines table<bpgen.StageContext, integer>
---@field loads table<bpgen.StageContext, number>  how many machines' worth of work the rate asks of the stage, a fraction
---@field rates table<bpgen.StageContext, bpgen.MachineRates>  what one machine of the stage does once its inserters fit its share

-- How many machines a stage gets for `wanted` items a minute of its product, and the
-- same for the stages that feed it. The root stage gets as many as the rate needs. A
-- stage that feeds another gets as many as make what the stage it feeds needs to make
-- its own share of the rate, not what all the machines of that stage could eat: asking
-- for 1 gear a minute takes 2 plates a minute, so one furnace, even though the
-- assembler could eat more. (The rate is at most what the belts carry, see
-- `planner.plan_tree`, so no stage gets more machines than its belts carry.) Also gives
-- each stage's load: how many machines' worth of work the rate asks of it, which is
-- not a whole number (1 gear a minute asks a fifth of a furnace's plates, say).
---@param stage bpgen.StageContext
---@param wanted number
---@param sizes bpgen.Sizes
local function size_stages(stage, wanted, sizes)
  local per_machine = stage.per_machine
  sizes.loads[stage] = wanted / per_machine.output
  sizes.machines[stage] = whole_machines(sizes.loads[stage])
  for _, supplier in ipairs(stage.suppliers) do
    size_stages(supplier, wanted * eaten_of(per_machine.inputs, supplier.request.product) / per_machine.output, sizes)
  end
end

-- What one machine of a stage does for the work the rate asks (`load`). A machine that
-- is used for less than a whole (the stage has one machine and its load is under 1)
-- needs only the inserters for the share it uses: a machine that takes two inserters
-- to run flat out takes one for 40%. With two or more machines the first ones run flat
-- out (the belt gives the machines at its start all they can take, and only the last
-- one runs part of the time), so they keep every inserter.
---@param stage bpgen.StageContext
---@param load number
---@return bpgen.MachineRates
local function stage_rates(stage, load)
  local limits = stage.request.inserters
  local used = math.min(load, 1) -- the share of its full speed the busiest machine runs at
  if not limits or used >= 1 - EPSILON then
    return stage.per_machine
  end
  local trimmed = {
    items_per_minute = limits.items_per_minute,
    max_input = math.min(limits.max_input, inserters_needed(used * total_per_minute(stage.per_machine.inputs), limits)),
    max_output = math.min(limits.max_output, inserters_needed(used * stage.per_machine.output, limits)),
  }
  local request = stage.request
  return rates_per_machine{
    product = request.product,
    recipe = request.recipe,
    machine_speed = request.machine_speed,
    fuel = request.fuel,
    inserters = trimmed,
  }
end

-- Fills in what one machine does for a stage and for the stages that feed it.
---@param stage bpgen.StageContext
---@param sizes bpgen.Sizes  with the loads filled in
local function size_rates(stage, sizes)
  sizes.rates[stage] = stage_rates(stage, sizes.loads[stage])
  for _, supplier in ipairs(stage.suppliers) do
    size_rates(supplier, sizes)
  end
end

---@param root bpgen.StageContext
---@param rate_per_minute number
---@return bpgen.Sizes
local function sizes_for(root, rate_per_minute)
  local sizes = {machines = {}, loads = {}, rates = {}}
  size_stages(root, rate_per_minute, sizes)
  size_rates(root, sizes)
  return sizes
end

-- The most of the root stage's product that a stage and the stages that feed it make
-- together, in items a minute. A stage makes what its machines make (`sizes` says how
-- many it has and what each does; nil for as many machines as its belts carry), but
-- no more than its belts carry, and the stage it feeds can only make as much as its
-- products allow. `needed` is how many items of the stage's product go into each item
-- of the root's.
---@param stage bpgen.StageContext
---@param needed number
---@param sizes? bpgen.Sizes
---@return number
local function final_output(stage, needed, sizes)
  local working = math.min(sizes and sizes.machines[stage] or math.huge, stage.machines_worth)
  local rates = sizes and sizes.rates[stage] or stage.per_machine
  local most = working * rates.output / needed
  for _, supplier in ipairs(stage.suppliers) do
    local supplier_needed = needed * eaten_of(stage.per_machine.inputs, supplier.request.product) / stage.per_machine.output
    most = math.min(most, final_output(supplier, supplier_needed, sizes))
  end
  return most
end

-- `machines` machines are built, but those past what the belts carry only wait, so
-- the stage makes and eats what its belts carry. A stage shown making less than that
-- (the root, when the stages before it cannot feed it fully) eats less as well.
---@param stage bpgen.StageContext
---@param machines integer
---@param load number  how many machines' worth of work the rate asks of the stage
---@param rates bpgen.MachineRates  what one machine of the stage does (see `stage_rates`)
---@param output? number  what the stage really makes a minute; all its machines can make by default
---@return bpgen.Plan
local function stage_plan(stage, machines, load, rates, output)
  local working = math.min(machines, stage.machines_worth)
  output = output or working * rates.output
  return {
    machines = machines,
    load = load,
    output_per_minute = output,
    inputs = total_inputs(stage.per_machine.inputs, output / stage.per_machine.output), -- the same fractions of its inputs and output, trimmed or not
    lanes = stage.lanes,
    input_inserters = rates.input_inserters,
    output_inserters = rates.output_inserters,
  }
end

-- The plans of a stage and of the stages that feed it. What the root stage makes is
-- what all the stages make together (`root_output`); an earlier stage shows what its
-- machines can make.
---@param stage bpgen.StageContext
---@param sizes bpgen.Sizes
---@param root_output? number  nil except for the root stage
---@return bpgen.PlanTree
local function plans_of(stage, sizes, root_output)
  local suppliers = {}
  for index, supplier in ipairs(stage.suppliers) do
    suppliers[index] = plans_of(supplier, sizes, nil)
  end
  local plan = stage_plan(stage, sizes.machines[stage], sizes.loads[stage], sizes.rates[stage], root_output)
  return {plan = plan, suppliers = suppliers}
end

-- request.rate_per_minute         how many of the root stage's product per minute
-- request.lane_items_per_minute   how many items one belt lane can carry per minute
-- request.root                    the stage that makes what the player wants, with
--                                 the stages that make its ingredients (see
--                                 `bpgen.StageTree`); each stage is
--   {product = item name, recipe = {energy = seconds,
--                                   ingredients = {{name = ..., amount = ...}},
--                                   products = {{name = ..., amount = ...}}},
--    machine_speed = the machine's crafting speed,
--    fuel = optional item the machine burns (a stage fed raw items only; it takes one
--           lane of the input belt),
--    inserters = optional {items_per_minute, max_input, max_output}: how much one
--           inserter moves, and how many inserters the input side and the output
--           side of a machine get. A machine that would need more runs slower, at
--           what they can move. Two output inserters put the product on both lanes
--           of the output belt, but only for the root stage}
--
-- A stage fed raw items shares the two lanes of its input belt among them and its
-- fuel: one item fills both lanes, two items get a lane each, and more are refused.
-- Any other stage eats exactly the products of the stages that feed it (at most two),
-- each on the one lane it travels on.
--
-- On success returns a tree of plans in the shape of the request's: for each stage
--   {machines, output_per_minute, inputs, lanes, input_inserters, output_inserters}
--   inputs   {{name, per_minute}, ...} what the machines eat in total, per ingredient
--   lanes    the item on each lane of the input belt (two entries for a stage fed raw
--            items, one for each made ingredient of any other)
--   *_inserters  inserters per machine, on each side
-- Each stage makes what the stages it feeds eat, and the root makes at least the rate
-- asked.
-- On failure returns nil, a reason string, and sometimes an extra value:
--   "unsupported-recipe"        a stage does not fit the belts, makes more than one
--                               product, or is not made by its product
--   "rate-too-high", max_rate   a belt lane cannot carry that rate, in some stage;
--                               max_rate is the most the root stage can make per
--                               minute in a single blueprint
--
-- Belt limits are counted in fractions of a machine (`machines_worth`): a lane that
-- carries 4.5 machines' worth feeds 5 machines, and the rate is limited by the lane.
---@param request bpgen.TreeRequest
---@return bpgen.PlanTree|nil plans
---@return bpgen.PlanReason|nil reason
---@return number|nil max_rate  only with "rate-too-high"
function planner.plan_tree(request)
  local root = stage_context(request.root, request, true)
  if not root then
    return nil, "unsupported-recipe"
  end
  local most = final_output(root, 1)
  if request.rate_per_minute > most + EPSILON then
    return nil, "rate-too-high", most
  end
  local sizes = sizes_for(root, request.rate_per_minute)
  return plans_of(root, sizes, final_output(root, 1, sizes))
end

-- The most the root stage of the request can make per minute in a single blueprint,
-- the same number `plan_tree` names with "rate-too-high". The request's rate is not
-- used. Returns nil and "unsupported-recipe" when some stage does not fit the belts.
---@param request bpgen.TreeRequest
---@return number|nil max_rate
---@return bpgen.PlanReason|nil reason
function planner.max_tree_rate(request)
  local root = stage_context(request.root, request, true)
  if not root then
    return nil, "unsupported-recipe"
  end
  return final_output(root, 1), nil
end

-- A chain is a tree in which every stage is fed by the one before it. Nil for no stages.
---@param stages bpgen.StageRequest[]  from the stage fed raw items to the last
---@return bpgen.StageTree|nil
local function chain_tree(stages)
  local tree
  for _, stage in ipairs(stages) do
    tree = {stage = stage, suppliers = tree and {tree} or {}}
  end
  return tree
end

-- The plans of a chain's tree as a list, first stage first.
---@param plans bpgen.PlanTree
---@return bpgen.Plan[]
local function chain_plans(plans)
  local list = {}
  local tree = plans
  while tree do
    table.insert(list, 1, tree.plan)
    tree = tree.suppliers[1]
  end
  return list
end

-- request.rate_per_minute         how many of the last stage's product per minute
-- request.lane_items_per_minute   how many items one belt lane can carry per minute
-- request.stages                  the stages in order, from the one fed raw items to
--                                 the one that makes what the player wants (see
--                                 `planner.plan_tree` for what a stage is)
--
-- A later stage eats only the product of the stage before it, which travels on one lane.
-- On success returns one plan table per stage, in the same order, with the fields
-- `plan_tree` names. On failure returns the same as `plan_tree`.
---@param request bpgen.ChainRequest
---@return bpgen.Plan[]|nil plans
---@return bpgen.PlanReason|nil reason
---@return number|nil max_rate  only with "rate-too-high"
function planner.plan_chain(request)
  local root = chain_tree(request.stages)
  if not root then
    return nil, "unsupported-recipe"
  end
  local plans, reason, max_rate = planner.plan_tree{
    rate_per_minute = request.rate_per_minute,
    lane_items_per_minute = request.lane_items_per_minute,
    root = root,
  }
  if not plans then
    return nil, reason, max_rate
  end
  return chain_plans(plans)
end

-- The most the last stage of the request can make per minute in a single column, the
-- same number `plan_chain` names with "rate-too-high". The request's rate is not used.
-- Returns nil and "unsupported-recipe" when some stage does not fit the belts.
---@param request bpgen.ChainRequest
---@return number|nil max_rate
---@return bpgen.PlanReason|nil reason
function planner.max_rate(request)
  local root = chain_tree(request.stages)
  if not root then
    return nil, "unsupported-recipe"
  end
  return planner.max_tree_rate{
    rate_per_minute = request.rate_per_minute,
    lane_items_per_minute = request.lane_items_per_minute,
    root = root,
  }
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
