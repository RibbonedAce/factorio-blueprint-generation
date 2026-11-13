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
local WINDING_MACHINE_SIZE = 3

-- The input belt of a stage has two lanes, so a stage fed raw items takes at most this
-- many items from it: its ingredients and its fuel. A stage fed by other stages has two
-- belts, one next to its machines and one beyond it (see `bpgen.Belts`), so it takes at
-- most twice as many ingredients, one on each lane.
local INPUT_LANES = 2
local MOST_INGREDIENTS = 2 * INPUT_LANES

-- Add up how many of `item_name` one craft of the recipe makes.
---@param recipe bpgen.Recipe
---@param item_name string
---@return number
function planner.amount_made(recipe, item_name)
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
  return planner.amount_made(recipe, product_name) > 0 and #recipe.products == 1 and recipe.energy > 0
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

-- How many inserters it takes to move `items_per_machine` a minute when one moves
-- `inserter_items_per_minute`: at least one.
---@param items_per_machine number
---@param inserter_items_per_minute number
---@return integer
local function inserters_needed(items_per_machine, inserter_items_per_minute)
  return math.max(1, math.ceil(items_per_machine / inserter_items_per_minute - EPSILON))
end

-- What one long-handed inserter moves a minute: the figure the limits give, or a plain
-- inserter's when they give none.
---@param limits bpgen.InserterLimits
---@return number
local function long_rate(limits)
  return limits.long_items_per_minute or limits.items_per_minute
end

-- Which ingredients ride which of the two input belts of a stage. Belt `a` is next to
-- the machines and plain inserters take from it; belt `b` is one column further out
-- and long-handed inserters take from it, over belt `a`. Each belt has two lanes, one
-- ingredient on each (a belt of raw items fills both lanes of its own).
---@class bpgen.Belts
---@field a string[]
---@field b string[]

-- How many inserters of each kind a machine's input side has.
---@class bpgen.InputInserters
---@field a integer  for belt a: plain ones, or fast ones when `fast`
---@field b integer  long-handed ones, for belt b
---@field fast? boolean  whether belt a's are fast ones; nil while the split is only being compared with others

-- What one machine eats of each ingredient and makes a minute at full speed.
---@param request bpgen.StageRequest
---@return bpgen.PlanInput[] inputs
---@return number output
local function full_speed(request)
  local recipe = request.recipe
  local crafts_per_minute = 60 * request.machine_speed / recipe.energy
  local inputs = {}
  for _, ingredient in ipairs(recipe.ingredients) do
    inputs[#inputs + 1] = {name = ingredient.name, per_minute = crafts_per_minute * ingredient.amount}
  end
  return inputs, crafts_per_minute * planner.amount_made(recipe, request.product)
end

-- How many items a minute the ingredients named in `names` add up to.
---@param inputs bpgen.PlanInput[]
---@param names string[]
---@return number
local function flow_of(inputs, names)
  local wanted = {}
  for _, name in ipairs(names) do
    wanted[name] = true
  end
  ---@type number
  local total = 0
  for _, input in ipairs(inputs) do
    if wanted[input.name] then
      total = total + input.per_minute
    end
  end
  return total
end

-- What one inserter of belt a and of the output side moves, as far as the planner counts: a fast one when the game
-- has them researched (`limits.fast_items_per_minute`), else a plain one. A side that needs it uses fast ones; one that
-- needs less uses a plain one (see `side_inserters`).
---@param limits bpgen.InserterLimits
---@return number
local function side_rate(limits)
  return limits.fast_items_per_minute or limits.items_per_minute
end

-- The inserters a side of a machine needs for `flow` items a minute: one plain inserter when that moves it, else fast
-- ones, as many as it takes, when the game has them; else plain ones, as many as it takes.
---@param flow number
---@param limits bpgen.InserterLimits
---@return integer count
---@return boolean fast
local function side_inserters(flow, limits)
  if flow <= limits.items_per_minute + EPSILON or not limits.fast_items_per_minute then
    return inserters_needed(flow, limits.items_per_minute), false
  end
  return inserters_needed(flow, limits.fast_items_per_minute), true
end

-- How much of its full speed a machine can use for what the inserters of its input
-- side can move: the belt that holds it back the most decides.
-- Belt a's inserters are fast ones when `counts.fast` says so, plain ones when it says not, and the best the game has
-- when it says nothing (a split being compared with others).
---@param flows {a: number, b: number}  items a minute that each belt brings, at full speed
---@param counts bpgen.InputInserters
---@param limits bpgen.InserterLimits
---@return number
local function input_fraction(flows, counts, limits)
  local rate_a = side_rate(limits)
  if counts.fast ~= nil then
    rate_a = counts.fast and limits.fast_items_per_minute or limits.items_per_minute
  end
  return math.min(
    side_fraction(flows.a, counts.a * rate_a),
    side_fraction(flows.b, counts.b * long_rate(limits)))
end

-- How the input slots of a machine are shared between the belts: all to belt a when belt b
-- carries nothing, otherwise the split (at least one slot each) that lets the machine run
-- fastest, the first one when several do. Nil when there are too few slots for two belts.
---@param flows {a: number, b: number}
---@param limits bpgen.InserterLimits
---@param has_b boolean  whether belt b carries anything
---@return bpgen.InputInserters|nil
local function allotted_counts(flows, limits, has_b)
  if not has_b then
    return {a = limits.max_input, b = 0}
  end
  local best, best_fraction
  for plain = 1, limits.max_input - 1 do
    local counts = {a = plain, b = limits.max_input - plain}
    local fraction = input_fraction(flows, counts, limits)
    if not best_fraction or fraction > best_fraction + EPSILON then
      best, best_fraction = counts, fraction
    end
  end
  return best
end

-- The counts cut down to what a machine that is used for `share` of its time needs:
-- a machine that takes two inserters to run flat out takes one for 40%.
---@param counts bpgen.InputInserters
---@param flows {a: number, b: number}
---@param limits bpgen.InserterLimits
---@param share number
---@return bpgen.InputInserters
local function trimmed_counts(counts, flows, limits, share)
  local needed, fast = side_inserters(share * flows.a, limits)
  return {
    a = math.min(counts.a, needed),
    fast = fast,
    b = counts.b == 0 and 0 or math.min(counts.b, inserters_needed(share * flows.b, long_rate(limits))),
  }
end

---@class bpgen.MachineRates  what ONE machine does each minute, once its inserters are counted
---@field output number  items of the product it makes
---@field inputs bpgen.PlanInput[]  what it eats, per ingredient, in the recipe's order
---@field input_inserters integer  inserters on its input side, for belt a
---@field input_fast boolean  whether those are fast inserters
---@field long_inserters integer  long-handed inserters on its input side, for belt b
---@field output_inserters integer  on its output side
---@field output_fast boolean  whether those are fast inserters

-- The inserters of a machine that runs at `fraction` of its full speed: what each side needs for the flow it then has.
---@param flows {a: number, b: number}
---@param output number  what it makes at full speed
---@param fraction number
---@param limits bpgen.InserterLimits
---@param has_b boolean
---@return {input: integer, input_fast: boolean, long: integer, output: integer, output_fast: boolean}
local function inserters_for(flows, output, fraction, limits, has_b)
  local input, input_fast = side_inserters(flows.a * fraction, limits)
  local output_count, output_fast = side_inserters(output * fraction, limits)
  return {
    input = input, input_fast = input_fast, long = has_b and inserters_needed(flows.b * fraction, long_rate(limits)) or 0,
    output = output_count, output_fast = output_fast,
  }
end

-- What ONE machine does each minute. When the inserters cannot keep up with it at
-- full speed, it simply waits for items, so every number shrinks by the same
-- fraction, and the inserters are counted for what it really moves. `share` is how
-- much of its full speed the busiest machine of the stage is used at. A machine that
-- is only partly used (`partial`: its share, and what it does at full use) gets only
-- the inserters that share needs. Returns nil when the machine has too few input slots
-- for both belts.
---@param request bpgen.StageRequest
---@param belts bpgen.Belts
---@param partial? {share: number, rates: bpgen.MachineRates}
---@return bpgen.MachineRates|nil
local function rates_per_machine(request, belts, partial)
  local inputs, output = full_speed(request)
  local limits = request.inserters
  local has_b = #belts.b > 0
  local flows = {a = flow_of(inputs, belts.a), b = flow_of(inputs, belts.b)}
  local fraction, counts = 1, {input = 1, input_fast = false, long = has_b and 1 or 0, output = 1, output_fast = false}
  if limits then
    local allotted = allotted_counts(flows, limits, has_b)
    if not allotted then
      return nil
    end
    local reference = partial and {
      flows = {a = flow_of(partial.rates.inputs, belts.a), b = flow_of(partial.rates.inputs, belts.b)},
      output = partial.rates.output,
      share = partial.share,
    } or {flows = flows, output = output, share = 1}
    local movable = trimmed_counts(allotted, reference.flows, limits, reference.share)
    local needed_out, out_fast = side_inserters(reference.share * reference.output, limits)
    local out_rate = out_fast and limits.fast_items_per_minute or limits.items_per_minute
    fraction = math.min(input_fraction(flows, movable, limits), side_fraction(output, math.min(limits.max_output, needed_out) * out_rate))
    counts = inserters_for(flows, output, fraction, limits, has_b)
  end
  for _, input in ipairs(inputs) do
    input.per_minute = input.per_minute * fraction
  end
  return {
    output = output * fraction,
    inputs = inputs,
    input_inserters = counts.input,
    input_fast = counts.input_fast,
    long_inserters = counts.long,
    output_inserters = counts.output,
    output_fast = counts.output_fast,
  }
end

-- How many whole machines it takes to do `machines_worth` of work: a fraction of a
-- machine still needs a whole one, and a stage always has at least one.
---@param machines_worth number
---@return integer
local function whole_machines(machines_worth)
  return math.max(1, math.ceil(machines_worth - EPSILON))
end

-- Whether the sides of the machines leave room for a winding belt: they are 3x3 and neither side is full. Not knowing
-- the size (`limits.machine_size` nil) leaves the question open and says yes.
---@param limits bpgen.InserterLimits
---@param rates bpgen.MachineRates
---@return boolean
local function room_for_winding(limits, rates)
  local size = limits.machine_size
  if size == nil then
    return true
  end
  return size == WINDING_MACHINE_SIZE and math.max(rates.input_inserters + rates.long_inserters, rates.output_inserters) < size
end

-- The winding a machine's output inserters ask for when the belt can wind: "double" for two of them, which fill a lane
-- each, "paired" for one fast one, which fills a lane when the machines go in twos (nil when the caller does not give the
-- machine's size, which leaves out the paired belt), and nil for a plain belt.
---@param limits bpgen.InserterLimits
---@param rates bpgen.MachineRates
---@return "double"|"paired"|nil
local function winding_asked_for(limits, rates)
  if rates.output_inserters == WINDING_OUTPUT_INSERTERS then
    return "double"
  end
  if limits.machine_size ~= nil and rates.output_inserters == 1 and rates.output_fast then
    return "paired"
  end
  return nil
end

-- How the output belt of the stage takes the product of its machines (see layout.lua), as "double" when it winds so
-- that the two output inserters of a machine fill a lane each, "paired" when it winds so that machines side by side, each
-- with one output inserter, fill a lane each, and nil when it is a plain belt with the product on one lane. The belt of a
-- stage built wide is paired, for any machine and whatever it feeds. Otherwise only the root stage's belt winds, and only
-- on a 3x3 machine whose sides are not full: a full side takes a row of poles between the
-- machines (a machine fits a pole when an inserter does not take every tile beside it), and a winding belt has no room for
-- that. `limits.machine_size` is nil when the caller does not say, which leaves out the size and the rows of poles, and
-- the paired belt.
---@param stage bpgen.StageContext
---@return "double"|"paired"|nil
local function output_winding(stage)
  if stage.wide then
    return "paired"
  end
  local limits, rates = stage.request.inserters, stage.per_machine
  if stage.winds and limits and room_for_winding(limits, rates) then
    return winding_asked_for(limits, rates)
  end
  return nil
end

-- How many machines' worth of product the output belt can take. With one output
-- inserter per machine the product is on one lane, which carries all of it. With
-- two, the winding belt (only the last stage's output belt winds) gives each
-- inserter a lane, but the first inserter takes all it can, so a lane can get
-- everything one inserter moves from every machine. (That is also why the two
-- lanes together never overfill: no machine makes more than two inserters move.)
-- An output belt that does not wind carries everything on its one lane, whatever
-- the inserters. With the paired winding belt every machine has one inserter, which
-- fills one lane, and machines alternate lanes (outer, inner, inner, outer, ...): a lane
-- gets half the machines, and the lane that gets one more for an odd number is the one the last
-- machine is on, which is the only one that may run for part of the time. A lane that carries L
-- machines' worth (a fraction) takes floor(L) whole machines and, when it has the last one, the rest of L.
-- So an even number of machines is at most twice floor(L) and an odd number floor(L) + L, which is
-- the most the belt carries, in machines' worth: 48 for L = 24 (24 machines on each lane), and never
-- less than a plain belt does.
---@param stage bpgen.StageContext
---@return number
local function output_machines_worth(stage)
  local lane_flow_per_machine = stage.per_machine.output
  local winding = output_winding(stage)
  if winding == "double" then
    local limits = stage.request.inserters --[[@as bpgen.InserterLimits]] -- a belt only winds when there are limits
    lane_flow_per_machine = stage.per_machine.output_fast and limits.fast_items_per_minute or limits.items_per_minute
  elseif winding == "paired" then
    local one_lane = stage.lane_items_per_minute / lane_flow_per_machine
    return math.floor(one_lane + EPSILON) + one_lane
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
---@field belts bpgen.Belts  which of its ingredients ride which input belt
---@field winds boolean  whether this stage's output belt may wind (only the root stage's can)
---@field per_machine bpgen.MachineRates
---@field wide boolean  whether the stage is built wide (see `bpgen.StageRequest.wide`)
---@field machines_worth number  how many machines' worth of work the belts of a column carry before a lane is full (not a whole number)

-- The lanes of a stage that burns fuel and is fed by another stage: the one ingredient that
-- stage makes on one lane (its products travel on one lane), the fuel on the other. Nil for
-- anything else: with a second ingredient, or a second stage feeding it, no lane is free.
---@param stage bpgen.StageRequest
---@param suppliers bpgen.StageContext[]
---@return string[]|nil lanes
---@return table<string, true>|nil raw  nothing: every ingredient is made
local function fuel_lanes(stage, suppliers)
  local ingredients = stage.recipe.ingredients
  if #ingredients ~= 1 or #suppliers ~= 1 or suppliers[1].request.product ~= ingredients[1].name then
    return nil
  end
  return {ingredients[1].name, stage.fuel}, {}
end

-- The lanes of a stage fed by one stage that is built wide: that stage's product rides both lanes of the belt between
-- them (see `takes_both_lanes`, which a stage that takes it so has), the lanes as they are for any other.
---@param lanes string[]  the ingredients, in the recipe's order
---@param suppliers bpgen.StageContext[]
---@return string[]
local function both_lanes_of_wide(lanes, suppliers)
  if suppliers[1] and suppliers[1].wide then
    lanes[2] = lanes[1]
  end
  return lanes
end

-- The items on the lanes of the belts that feed a stage, or nil when they do not
-- fit. A stage fed raw items shares the two lanes of its belt among them and its fuel
-- (see `assign_lanes`). Every other stage eats the products of the stages that feed it,
-- each on the one lane its product travels on, and at most one raw item, which has no
-- stage (nothing could put a fuel on those belts), so it has at most four ingredients.
-- The stages that feed it make ingredients of its recipe, in any order. The one exception
-- is a stage that burns fuel and eats one made ingredient (see `fuel_lanes`).
---@param stage bpgen.StageRequest
---@param suppliers bpgen.StageContext[]  the stages that feed it
---@return string[]|nil lanes  the ingredients, in the recipe's order
---@return table<string, true>|nil raw  the ingredients that no stage makes; nil for a stage fed raw items
local function stage_lanes(stage, suppliers)
  if #suppliers == 0 then
    return assign_lanes(stage.recipe.ingredients, stage.fuel)
  end
  local ingredients = stage.recipe.ingredients
  if stage.fuel then
    return fuel_lanes(stage, suppliers)
  end
  if #ingredients > MOST_INGREDIENTS then
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
  return both_lanes_of_wide(lanes, suppliers), unmade
end

-- The ingredients on belts a and b for one way of splitting them: the ingredients whose
-- bit is set in `mask` go on belt b. Nil when a belt would have more than two, or a raw
-- ingredient would go on belt b (a belt of raw items fills both lanes, so it can only be
-- side-loaded onto belt a). Also gives how late in the recipe the ingredients of belt b
-- are, as the sum of their places.
---@param lanes string[]
---@param mask integer
---@param raw table<string, true>
---@return bpgen.Belts|nil
---@return integer|nil later
local function split_ingredients(lanes, mask, raw)
  local belts, later = {a = {}, b = {}}, 0
  for index, name in ipairs(lanes) do
    if math.floor(mask / 2 ^ (index - 1)) % 2 == 1 then
      if raw[name] then
        return nil
      end
      belts.b[#belts.b + 1] = name
      later = later + index
    else
      belts.a[#belts.a + 1] = name
    end
  end
  if #belts.a > INPUT_LANES or #belts.b > INPUT_LANES then
    return nil
  end
  return belts, later
end

-- How much of its full speed a machine can use for this split, or nil when its slots
-- cannot serve both belts. Without an inserter limit every split is as good.
---@param inputs bpgen.PlanInput[]
---@param belts bpgen.Belts
---@param limits bpgen.InserterLimits|nil
---@return number|nil
local function split_fraction(inputs, belts, limits)
  if not limits then
    return 1
  end
  local flows = {a = flow_of(inputs, belts.a), b = flow_of(inputs, belts.b)}
  local counts = allotted_counts(flows, limits, true)
  return counts and input_fraction(flows, counts, limits)
end

-- Whether a split beats the best so far: it runs the machine faster, or equally fast with
-- fewer ingredients on belt b, or equally fast with as many there but later in the recipe.
---@param candidate {fraction: number, belts: bpgen.Belts, later: integer}
---@param best {fraction: number, belts: bpgen.Belts, later: integer}|nil
---@return boolean
local function is_better(candidate, best)
  if not best then
    return true
  end
  if math.abs(candidate.fraction - best.fraction) > EPSILON then
    return candidate.fraction > best.fraction
  end
  if #candidate.belts.b ~= #best.belts.b then
    return #candidate.belts.b < #best.belts.b
  end
  return candidate.later > best.later
end

-- Which ingredients ride which belt. A stage with up to two ingredients keeps them all on
-- belt a. With three or four, the split that lets a machine run fastest (see
-- `is_better`): it depends only on what one machine eats, not on the rate. Nil when no
-- split fits.
---@param stage bpgen.StageRequest
---@param lanes string[]
---@param raw table<string, true>
---@return bpgen.Belts|nil
local function choose_belts(stage, lanes, raw)
  if #lanes <= INPUT_LANES then
    return {a = lanes, b = {}}
  end
  local inputs = full_speed(stage)
  local best
  for mask = 1, 2 ^ #lanes - 1 do
    local belts, later = split_ingredients(lanes, mask, raw)
    local fraction = belts and split_fraction(inputs, belts, stage.inserters)
    if belts and fraction then
      local candidate = {fraction = fraction, belts = belts, later = later}
      if is_better(candidate, best) then
        best = candidate
      end
    end
  end
  return best and best.belts
end

-- Whether a stage takes the product of the stage that feeds it on both lanes of one belt: it eats that product and
-- nothing else (no second ingredient, no fuel, whose lane the product would have to leave free), so a supplier built wide,
-- which puts its product on both lanes, can feed it. (A stage with one ingredient has one supplier at most.) A stage that
-- burns fuel takes plates on both lanes only when it is built wide too (it has a belt of its own for the fuel), which it is
-- when it asks for it and the tree allows it (`may_widen`): its supplier is not built wide for nothing otherwise.
---@param stage bpgen.StageRequest
---@param may_widen boolean  whether the tree allows `stage` itself to be built wide
---@return boolean
local function takes_both_lanes(stage, may_widen)
  return #stage.recipe.ingredients == 1 and (stage.fuel == nil or (stage.wide == true and may_widen))
end

-- Whether a stage is of the kind that is built wide (see `bpgen.StageRequest.wide`): it asks for it, burns fuel and eats
-- one ingredient, and it is fed raw items (its belt has a lane of each, and a second belt) or by a stage that is built wide
-- (the plates on both lanes of the belt, and a belt of its own for the fuel).
---@param stage bpgen.StageRequest
---@param suppliers bpgen.StageContext[]
---@return boolean
local function is_wide_kind(stage, suppliers)
  local fed_wide = #suppliers == 1 and suppliers[1].wide
  return stage.wide == true and stage.fuel ~= nil and #stage.recipe.ingredients == 1 and (#suppliers == 0 or fed_wide)
end

-- Whether the sides of a machine are what a stage built wide has: the layout knows the size of the machine, and a plain
-- inserter on each side moves what it needs (the second plain inserter, for belt b, then fills the input side).
---@param stage bpgen.StageRequest
---@param per_machine bpgen.MachineRates
---@return boolean
local function has_wide_sides(stage, per_machine)
  return stage.inserters ~= nil and stage.inserters.machine_size ~= nil
    and per_machine.input_inserters == 1 and per_machine.long_inserters == 0 and per_machine.output_inserters == 1
end

-- Whether a stage may be built wide.
---@param stage bpgen.StageRequest
---@param suppliers bpgen.StageContext[]
---@param per_machine bpgen.MachineRates
---@return boolean
local function can_be_wide(stage, suppliers, per_machine)
  return is_wide_kind(stage, suppliers) and has_wide_sides(stage, per_machine)
end

-- The four lanes of the two input belts of a stage built wide, from the two of the belt it would have. A stage fed raw
-- items keeps its ingredient and its fuel on belt a, and belt b carries the ingredient on both lanes. A stage fed by one
-- built wide has the ingredient on both lanes of the belt before it, and its fuel on both lanes of a belt of its own.
---@param lanes string[]  the ingredient and the fuel
---@param suppliers bpgen.StageContext[]
---@return string[]
local function wide_lanes(lanes, suppliers)
  if #suppliers == 0 then
    return {lanes[1], lanes[2], lanes[1], lanes[1]}
  end
  return {lanes[1], lanes[1], lanes[2], lanes[2]}
end

-- What one machine does when it has a second plain input inserter, for belt b.
---@param rates bpgen.MachineRates
---@return bpgen.MachineRates
local function with_second_inserter(rates)
  local wide = {}
  for key, value in pairs(rates) do
    wide[key] = value
  end
  wide.input_inserters = 2
  return wide
end

-- Whether a stage is built wide, with the lanes and the machine rates that go with it (as they were worked out when it is
-- not). `may_widen` is whether the tree asks for it of this stage (see `stage_context`). (A stage that burns fuel and
-- cannot be built wide after one that is, whose plates then fill both lanes of its belt and leave none for the fuel, is
-- planned with the lanes of a plain stage, so it makes no more than the plain design: the rate asked is refused.)
---@param stage bpgen.StageRequest
---@param suppliers bpgen.StageContext[]
---@param lanes string[]
---@param per_machine bpgen.MachineRates
---@param may_widen boolean
---@return boolean wide
---@return string[] lanes
---@return bpgen.MachineRates per_machine
local function widened(stage, suppliers, lanes, per_machine, may_widen)
  if not (may_widen and can_be_wide(stage, suppliers, per_machine)) then
    return false, lanes, per_machine
  end
  return true, wide_lanes(lanes, suppliers), with_second_inserter(per_machine)
end

-- The lanes, the belts and what one machine does for a stage fed by `suppliers`, before it is built wide, or nil when it
-- does not fit (see `stage_lanes`, `is_supported`).
---@param stage bpgen.StageRequest
---@param suppliers bpgen.StageContext[]
---@return string[]|nil lanes
---@return bpgen.Belts|nil belts
---@return bpgen.MachineRates|nil per_machine
local function machine_setup(stage, suppliers)
  local lanes, raw = stage_lanes(stage, suppliers)
  if not lanes or not is_supported(stage.recipe, stage.product) then
    return nil
  end
  local belts = choose_belts(stage, lanes, raw or {})
  local per_machine = belts and rates_per_machine(stage, belts)
  if not per_machine then
    return nil
  end
  return lanes, belts, per_machine
end

local stage_context -- defined below: a stage is worked out with the stages that feed it

-- The contexts of the stages that feed a stage, or nil when one of them does not fit. A stage that feeds a stage that takes
-- its product on both lanes (see `takes_both_lanes`) may be built wide where `widen` says so.
---@param tree bpgen.StageTree
---@param request bpgen.TreeRequest
---@param widen boolean
---@param may_widen boolean  whether the tree allows the stage itself to be built wide
---@return bpgen.StageContext[]|nil
local function supplier_contexts(tree, request, widen, may_widen)
  local suppliers = {}
  local suppliers_may_widen = widen and takes_both_lanes(tree.stage, may_widen)
  for index, supplier in ipairs(tree.suppliers) do
    suppliers[index] = stage_context(supplier, request, false, widen, suppliers_may_widen)
    if not suppliers[index] then
      return nil
    end
  end
  return suppliers
end

-- Everything the planner works out about a stage and the stages that feed it before
-- it is asked for a rate, or nil when one of them does not fit (see `stage_lanes`,
-- `is_supported`). Only the root stage may wind its output belt, but for the stages built wide: a stage is built wide when
-- `may_widen` (the tree is built that way, and the stage is the root or feeds a stage that takes its product on both
-- lanes) and it is of the kind that can be (see `can_be_wide`).
---@param tree bpgen.StageTree
---@param request bpgen.TreeRequest
---@param is_root boolean
---@param widen boolean  build the stages that can be built wide that way
---@param may_widen boolean  this stage may be one of them
---@return bpgen.StageContext|nil
function stage_context(tree, request, is_root, widen, may_widen)
  local suppliers = supplier_contexts(tree, request, widen, may_widen)
  if not suppliers then
    return nil
  end
  local stage = tree.stage
  local lanes, belts, per_machine = machine_setup(stage, suppliers)
  if not (lanes and belts and per_machine) then
    return nil
  end
  local wide
  wide, lanes, per_machine = widened(stage, suppliers, lanes, per_machine, may_widen)
  ---@type bpgen.StageContext
  local context = {
    request = stage, suppliers = suppliers, lane_items_per_minute = request.lane_items_per_minute,
    lanes = lanes, belts = belts, winds = is_root, wide = wide, per_machine = per_machine, machines_worth = 0,
  }
  context.machines_worth = machines_per_belt(context)
  return context
end

-- The context of the whole tree, whose root may be built wide when `widen` says the tree is.
---@param request bpgen.TreeRequest
---@param widen boolean
---@return bpgen.StageContext|nil
local function root_context(request, widen)
  return stage_context(request.root, request, true, widen, widen)
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
  if not limits or used >= 1 - EPSILON or stage.wide then
    return stage.per_machine
  end
  return rates_per_machine(stage.request, stage.belts, {share = used, rates = stage.per_machine}) --[[@as bpgen.MachineRates]] -- it fitted once, at full speed
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
    belts = stage.belts,
    input_inserters = rates.input_inserters,
    input_fast = rates.input_fast,
    long_inserters = rates.long_inserters,
    output_inserters = rates.output_inserters,
    output_fast = rates.output_fast,
    wide = stage.wide,
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
--    fuel = optional item the machine burns (a stage fed raw items, or one that eats
--           one made ingredient; it takes one lane of the input belt),
--    inserters = optional {items_per_minute, long_items_per_minute, max_input,
--           max_output}: how much one inserter (and one long-handed inserter, a plain
--           one's figure when left out) moves, and how many inserters the input side
--           (shared between plain and long-handed ones) and the output side of a
--           machine get. A machine that would need more runs slower, at what they can
--           move. Two output inserters put the product on both lanes of the output
--           belt, but only for the root stage}
--
-- A stage fed raw items shares the two lanes of its input belt among them and its
-- fuel: one item fills both lanes, two items get a lane each, and more are refused. A
-- stage that burns fuel and eats the one product of the stage before it (steel plate from
-- iron plates) has that product on one lane and the fuel on the other.
-- Any other stage eats the products of the stages that feed it, and at most one raw
-- item more, each on the one lane it travels on. With one or two ingredients they all
-- ride the belt next to the machines (belt a). With three or four there is a second
-- belt (b), reached by long-handed inserters, and the planner splits the ingredients
-- between the belts, at most two on each and a raw one only on belt a, so that a
-- machine runs fastest (`choose_belts`).
--
-- On success returns a tree of plans in the shape of the request's: for each stage
--   {machines, output_per_minute, inputs, lanes, belts, input_inserters,
--    long_inserters, output_inserters}
--   inputs   {{name, per_minute}, ...} what the machines eat in total, per ingredient
--   lanes    the item on each lane of the input belts (two entries for a stage fed raw
--            items, one for each ingredient of any other)
--   belts    {a = {...}, b = {...}} which ingredients ride which belt
--   *_inserters  inserters per machine: plain ones for belt a and the input side,
--            long-handed ones for belt b, plain ones for the output side
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
  local root = root_context(request, false)
  if not root then
    return nil, "unsupported-recipe"
  end
  if request.rate_per_minute > final_output(root, 1) + EPSILON then
    root = root_context(request, true) --[[@as bpgen.StageContext]] -- it fits when the same stages do, narrow
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
  local root = root_context(request, true)
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
