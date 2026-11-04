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

-- What ONE machine does each minute: how much it makes, and how much of each
-- ingredient it eats (in the recipe's order). When the inserters cannot keep up
-- with it at full speed, it simply waits for items, so every number shrinks by
-- the same fraction.
---@param recipe bpgen.Recipe  one that `is_supported`
---@param machine_speed number
---@param made_per_craft number
---@param inserters bpgen.InserterLimits|nil
---@return number output_per_minute
---@return bpgen.PlanInput[] inputs  what it eats of each ingredient
local function rates_per_machine(recipe, machine_speed, made_per_craft, inserters)
  local crafts_per_minute = 60 * machine_speed / recipe.energy
  local output = crafts_per_minute * made_per_craft
  local inputs = {}
  for _, ingredient in ipairs(recipe.ingredients) do
    inputs[#inputs + 1] = {name = ingredient.name, per_minute = crafts_per_minute * ingredient.amount}
  end
  local fraction = usable_fraction(total_per_minute(inputs), output, inserters)
  for _, input in ipairs(inputs) do
    input.per_minute = input.per_minute * fraction
  end
  return output * fraction, inputs
end

---@param rate_per_minute number
---@param output_per_machine number
---@return integer
local function machines_needed(rate_per_minute, output_per_machine)
  return math.max(1, math.ceil(rate_per_minute / output_per_machine - EPSILON))
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

-- How many machines the output belt can take. With one output inserter per
-- machine the product is on one lane, which carries all of it. With two, the
-- winding belt gives each inserter a lane, but the first inserter takes all it
-- can, so a lane can get everything one inserter moves from every machine. (That
-- is also why the two lanes together never overfill: no machine makes more than
-- two inserters move.)
---@param lane_items_per_minute number
---@param output_per_machine number
---@param output_inserters integer
---@param inserters bpgen.InserterLimits|nil
---@return integer
local function output_machine_limit(lane_items_per_minute, output_per_machine, output_inserters, inserters)
  local lane_flow_per_machine = output_per_machine
  if output_inserters == WINDING_OUTPUT_INSERTERS and inserters then
    lane_flow_per_machine = inserters.items_per_minute
  end
  return math.floor(lane_items_per_minute / lane_flow_per_machine + EPSILON)
end

-- How many machines one column can serve before a belt lane is full: the
-- output belt, and the lanes that carry each ingredient (two lanes for an
-- ingredient that has the belt to itself).
---@param request bpgen.PlanRequest
---@param lanes string[]
---@param output_per_machine number
---@param inputs_per_machine bpgen.PlanInput[]
---@return integer
local function machines_per_belt(request, lanes, output_per_machine, inputs_per_machine)
  local lane = request.lane_items_per_minute
  local output_inserters = inserters_needed(output_per_machine, request.inserters)
  local most = output_machine_limit(lane, output_per_machine, output_inserters, request.inserters)
  for _, input in ipairs(inputs_per_machine) do
    most = math.min(most, math.floor(lanes_carrying(lanes, input.name) * lane / input.per_minute + EPSILON))
  end
  return most
end

-- What all the machines eat together, in the recipe's order.
---@param inputs_per_machine bpgen.PlanInput[]
---@param machines integer
---@return bpgen.PlanInput[]
local function total_inputs(inputs_per_machine, machines)
  local totals = {}
  for _, input in ipairs(inputs_per_machine) do
    totals[#totals + 1] = {name = input.name, per_minute = machines * input.per_minute}
  end
  return totals
end

-- request.product         item the player wants
-- request.rate_per_minute how many of it per minute
-- request.recipe          {energy = seconds,
--                          ingredients = {{name = ..., amount = ...}},
--                          products = {{name = ..., amount = ...}}}
-- request.machine_speed   the machine's crafting speed
-- request.lane_items_per_minute  how many items one belt lane can carry per minute
-- request.fuel            optional, the item the machine burns; it takes one lane
--                         of the input belt
-- request.inserters       optional, {items_per_minute, max_input, max_output}: how much
--                         one inserter moves, and how many inserters the input side and
--                         the output side of a machine get. A machine that would need
--                         more runs slower, at what they can move. Two output inserters
--                         put the product on both lanes of the output belt
--
-- The recipe's ingredients and the fuel share the two lanes of the input belt:
-- one item fills both lanes, two items get a lane each, and more are refused.
--
-- On success returns a plan table:
--   {machines, output_per_minute, inputs, lanes, input_inserters, output_inserters}
--   inputs   {{name, per_minute}, ...} what the machines eat in total, per ingredient
--   lanes    {first lane's item, second lane's item}
--   *_inserters  inserters per machine, on each side
-- On failure returns nil, a reason string, and sometimes an extra value:
--   "unsupported-recipe"        the recipe or its fuel does not fit the input belt, makes
--                               more than one product, or is not made by the product
--   "rate-too-high", max_rate   a belt lane cannot carry that rate; max_rate is the
--                               most a single column can make per minute
---@param request bpgen.PlanRequest
---@return bpgen.Plan|nil plan
---@return "unsupported-recipe"|"rate-too-high"|nil reason
---@return number|nil max_rate  only with "rate-too-high"
function planner.plan(request)
  local recipe = request.recipe
  local lanes = assign_lanes(recipe.ingredients, request.fuel)
  if not lanes or not is_supported(recipe, request.product) then
    return nil, "unsupported-recipe"
  end

  local made_per_craft = amount_made(recipe, request.product)
  local output_per_machine, inputs_per_machine =
    rates_per_machine(recipe, request.machine_speed, made_per_craft, request.inserters)
  local most = machines_per_belt(request, lanes, output_per_machine, inputs_per_machine)
  local machines = machines_needed(request.rate_per_minute, output_per_machine)
  if machines > most then
    return nil, "rate-too-high", most * output_per_machine
  end

  return {
    machines = machines,
    output_per_minute = machines * output_per_machine,
    inputs = total_inputs(inputs_per_machine, machines),
    lanes = lanes,
    input_inserters = inserters_needed(total_per_minute(inputs_per_machine), request.inserters),
    output_inserters = inserters_needed(output_per_machine, request.inserters),
  }
end

return planner
