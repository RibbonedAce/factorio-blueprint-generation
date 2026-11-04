-- scripts/planner.lua
-- Pure maths: how many machines does a product rate need?
-- It never touches the game (no `game`, no `prototypes`), so it can be tested
-- outside Factorio. The caller passes in plain tables with the numbers.

local planner = {}

-- Decimal numbers like 3.2 cannot be stored exactly, so 18.75 / 18.749999999999996
-- can come out as 1.0000000000000002 and round up to a whole extra machine.
-- Subtracting a tiny amount before rounding up avoids that.
local EPSILON = 1e-9

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

-- Whether this planner can handle the recipe: it must make the product, have
-- exactly one ingredient, and take time to craft.
---@param recipe bpgen.Recipe
---@param made_per_craft number
---@return boolean
local function is_supported(recipe, made_per_craft)
  return made_per_craft > 0 and #recipe.ingredients == 1 and recipe.energy > 0
end

-- What ONE machine does each minute: how much it makes and how much it eats.
---@param recipe bpgen.Recipe  one that `is_supported`, so it has exactly one ingredient
---@param machine_speed number
---@param made_per_craft number
---@return number output_per_minute
---@return number input_per_minute
local function rates_per_machine(recipe, machine_speed, made_per_craft)
  local ingredient = recipe.ingredients[1]
  ---@cast ingredient -?
  local crafts_per_minute = 60 * machine_speed / recipe.energy
  return crafts_per_minute * made_per_craft, crafts_per_minute * ingredient.amount
end

---@param rate_per_minute number
---@param output_per_machine number
---@return integer
local function machines_needed(rate_per_minute, output_per_machine)
  return math.max(1, math.ceil(rate_per_minute / output_per_machine - EPSILON))
end

-- The input and the output each travel on one belt lane, so the busier of the
-- two decides how many machines one column can serve.
---@param lane_items_per_minute number
---@param output_per_machine number
---@param input_per_machine number
---@return integer
local function machines_per_lane(lane_items_per_minute, output_per_machine, input_per_machine)
  local busiest_flow = math.max(output_per_machine, input_per_machine)
  return math.floor(lane_items_per_minute / busiest_flow + EPSILON)
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

-- How many machines the rate needs. Returns nothing but the most one belt lane
-- can carry (in output items a minute) when it needs more machines than one lane serves.
---@param rate_per_minute number
---@param output_per_machine number
---@param input_per_machine number
---@param lane_items_per_minute number
---@return integer|nil machines
---@return number|nil max_rate
local function machine_count(rate_per_minute, output_per_machine, input_per_machine, lane_items_per_minute)
  local machines = machines_needed(rate_per_minute, output_per_machine)
  local max_machines = machines_per_lane(lane_items_per_minute, output_per_machine, input_per_machine)
  if machines > max_machines then
    return nil, max_machines * output_per_machine
  end
  return machines, nil
end

-- Inserters per machine, on the input side and on the output side. Returns
-- nothing when one side needs more than fit around the machine.
---@param input_per_machine number
---@param output_per_machine number
---@param inserters bpgen.InserterLimits|nil
---@return integer|nil input_inserters
---@return integer|nil output_inserters
local function inserter_counts(input_per_machine, output_per_machine, inserters)
  local input_inserters = inserters_needed(input_per_machine, inserters)
  local output_inserters = inserters_needed(output_per_machine, inserters)
  if inserters and math.max(input_inserters, output_inserters) > inserters.max_per_side then
    return nil, nil
  end
  return input_inserters, output_inserters
end

-- product_name        item the player wants
-- rate_per_minute     how many of it per minute
-- recipe              {energy = seconds,
--                      ingredients = {{name = ..., amount = ...}},
--                      products = {{name = ..., amount = ...}}}
-- machine_speed       the machine's crafting speed
-- lane_items_per_minute  how many items one belt lane can carry per minute
-- inserters           optional, {items_per_minute, max_per_side}: how much one inserter
--                     moves, and how many inserters fit on one side of the machine
--
-- On success returns a plan table:
--   {machines, output_per_minute, ingredient, ingredient_per_minute,
--    input_inserters, output_inserters}   (inserters per machine, on each side)
-- On failure returns nil, a reason string, and sometimes an extra value:
--   "unsupported-recipe"        the recipe is not "one ingredient -> product"
--   "inserters-do-not-fit"      a machine needs more inserters on one side than fit
--   "rate-too-high", max_rate   one belt lane cannot carry that rate; max_rate is the
--                               most a single column can make per minute
---@param product_name string
---@param rate_per_minute number
---@param recipe bpgen.Recipe
---@param machine_speed number
---@param lane_items_per_minute number
---@param inserters? bpgen.InserterLimits
---@return bpgen.Plan|nil plan
---@return "unsupported-recipe"|"inserters-do-not-fit"|"rate-too-high"|nil reason
---@return number|nil max_rate  only with "rate-too-high"
function planner.plan(product_name, rate_per_minute, recipe, machine_speed, lane_items_per_minute, inserters)
  local made_per_craft = amount_made(recipe, product_name)
  if not is_supported(recipe, made_per_craft) then
    return nil, "unsupported-recipe"
  end

  local output_per_machine, input_per_machine = rates_per_machine(recipe, machine_speed, made_per_craft)
  local input_inserters, output_inserters = inserter_counts(input_per_machine, output_per_machine, inserters)
  if not input_inserters then
    return nil, "inserters-do-not-fit"
  end
  ---@cast output_inserters -? -- `inserter_counts` gives both or neither

  local machines, max_rate = machine_count(rate_per_minute, output_per_machine, input_per_machine, lane_items_per_minute)
  if not machines then
    return nil, "rate-too-high", max_rate
  end

  return {
    machines = machines,
    output_per_minute = machines * output_per_machine,
    ingredient = (recipe.ingredients[1] --[[@as bpgen.RecipeItem]]).name, -- `is_supported` made sure there is exactly one
    ingredient_per_minute = machines * input_per_machine,
    input_inserters = input_inserters,
    output_inserters = output_inserters,
  }
end

return planner
